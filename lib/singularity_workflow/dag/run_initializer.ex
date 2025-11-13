defmodule Singularity.Workflow.DAG.RunInitializer do
  @moduledoc """
  Initializes a workflow run in the database - creates all necessary records
  for database-driven DAG execution.

  ## Initialization Steps

  1. Create workflow_runs record with status='started'
  2. Create workflow_step_states records for each step
     - Set remaining_deps based on dependency count
     - Set initial_tasks (supports map steps with N tasks)
  3. Create workflow_step_dependencies records
  4. Ensure pgmq queue exists for this workflow
  5. Call start_ready_steps() to:
     - Mark root steps as 'started'
     - Create workflow_step_tasks records
     - Send messages to pgmq queue (matches Singularity.Workflow architecture)

  ## Example

      {:ok, definition} = WorkflowDefinition.parse(MyWorkflow)
      {:ok, run_id} = RunInitializer.initialize(definition, %{"user_id" => 123}, MyApp.Repo)

      # Database now contains:
      # - 1 workflow_runs record
      # - N workflow_step_states records (one per step)
      # - M workflow_step_dependencies records
      # - K workflow_step_tasks records (for root steps)
  """

  require Logger

  import Ecto.Query

  alias Singularity.Workflow.DAG.WorkflowDefinition
  alias Singularity.Workflow.FlowTracer
  alias Singularity.Workflow.StepDependency
  alias Singularity.Workflow.StepState
  alias Singularity.Workflow.WorkflowRun

  @doc """
  Initialize a workflow run with all database records.

  Returns `{:ok, run_id}` on success.
  """
  @spec initialize(WorkflowDefinition.t(), map(), module()) ::
          {:ok, Ecto.UUID.t()} | {:error, term()}
  def initialize(%WorkflowDefinition{} = definition, input, repo) do
    repo.transaction(fn ->
      with {:ok, run} <- create_run(definition, input, repo),
           :ok <- create_workflow_steps(definition, repo),
           :ok <- create_step_states(definition, run.id, repo),
           :ok <- create_dependencies(definition, run.id, repo),
           :ok <- trace_workflow_structure(definition, run.id),
           :ok <- ensure_workflow_queue(definition.slug, repo),
           :ok <- start_ready_steps(run.id, repo) do
        run.id
      else
        {:error, reason} ->
          repo.rollback(reason)
      end
    end)
  end

  # Step 1: Create workflow_runs record
  @spec create_run(WorkflowDefinition.t(), map(), module()) ::
          {:ok, WorkflowRun.t()} | {:error, term()}
  defp create_run(definition, input, repo) do
    run_id = Ecto.UUID.generate()
    step_count = map_size(definition.steps)
    clock = Application.get_env(:singularity_workflow, :clock, Singularity.Workflow.Clock)

    %WorkflowRun{}
    |> WorkflowRun.changeset(%{
      id: run_id,
      workflow_slug: definition.slug,
      status: "started",
      input: input,
      remaining_steps: step_count,
      started_at: clock.now()
    })
    |> repo.insert()
  end

  # Step 1.5: Create workflow_steps records for code-based workflows
  # (FlowBuilder workflows already have these records)
  @spec create_workflow_steps(WorkflowDefinition.t(), module()) :: :ok | {:error, term()}
  defp create_workflow_steps(definition, repo) do
    # Check if workflow_steps already exist for this workflow
    existing_count =
      repo.one(
        from(ws in "workflow_steps",
          where: ws.workflow_slug == ^definition.slug,
          select: count(ws.workflow_slug)
        )
      )

    if existing_count > 0 do
      # Workflow steps already exist (FlowBuilder workflow)
      :ok
    else
      # Check if workflow record exists, create if not (for code-based workflows)
      workflow_exists =
        repo.one(
          from(w in "workflows",
            where: w.workflow_slug == ^definition.slug,
            select: count(w.workflow_slug)
          )
        )

      with :ok <- create_workflow_record_if_needed(definition, repo, workflow_exists),
           :ok <- create_workflow_step_records(definition, repo) do
        :ok
      else
        error -> error
      end
    end
  end

  @spec create_workflow_record_if_needed(WorkflowDefinition.t(), module(), integer()) ::
          :ok | {:error, term()}
  defp create_workflow_record_if_needed(definition, repo, 0) do
    # Create workflow record for code-based workflow
    clock = Application.get_env(:singularity_workflow, :clock, Singularity.Workflow.Clock)

    workflow_record = %{
      workflow_slug: definition.slug,
      max_attempts: 3,
      timeout: 60,
      created_at: clock.now()
    }

    case repo.insert_all("workflows", [workflow_record]) do
      {1, _} -> :ok
      _ -> {:error, :workflow_creation_failed}
    end
  end

  @spec create_workflow_record_if_needed(WorkflowDefinition.t(), module(), integer()) :: :ok
  defp create_workflow_record_if_needed(_definition, _repo, _), do: :ok

  @spec create_workflow_step_records(WorkflowDefinition.t(), module()) :: :ok | {:error, term()}
  defp create_workflow_step_records(definition, repo) do
    clock = Application.get_env(:singularity_workflow, :clock, Singularity.Workflow.Clock)

    step_records =
      Enum.with_index(definition.steps, 1)
      |> Enum.map(fn {{step_name, _step_fn}, index} ->
        _metadata = WorkflowDefinition.get_step_metadata(definition, step_name)

        %{
          workflow_slug: definition.slug,
          step_slug: to_string(step_name),
          step_index: index,
          # Code-based workflows are always single steps
          step_type: "single",
          deps_count: WorkflowDefinition.dependency_count(definition, step_name),
          created_at: clock.now()
        }
      end)

    case repo.insert_all("workflow_steps", step_records) do
      {count, _} when count == map_size(definition.steps) -> :ok
      _ -> {:error, :workflow_steps_insert_failed}
    end
  end

  # Step 2: Create workflow_step_states records
  @spec create_step_states(WorkflowDefinition.t(), Ecto.UUID.t(), module()) ::
          :ok | {:error, term()}
  defp create_step_states(definition, run_id, repo) do
    clock = Application.get_env(:singularity_workflow, :clock, Singularity.Workflow.Clock)

    step_states =
      Enum.map(definition.steps, fn {step_name, _step_fn} ->
        remaining_deps = WorkflowDefinition.dependency_count(definition, step_name)
        metadata = WorkflowDefinition.get_step_metadata(definition, step_name)

        %{
          run_id: run_id,
          step_slug: to_string(step_name),
          workflow_slug: definition.slug,
          status: "created",
          remaining_deps: remaining_deps,
          initial_tasks: metadata.initial_tasks,
          inserted_at: clock.now(),
          updated_at: clock.now()
        }
      end)

    {count, _} = repo.insert_all(StepState, step_states)

    if count == map_size(definition.steps) do
      :ok
    else
      {:error, :step_states_insert_failed}
    end
  end

  # Step 3: Create workflow_step_dependencies records
  @spec create_dependencies(WorkflowDefinition.t(), Ecto.UUID.t(), module()) :: :ok
  defp create_dependencies(definition, run_id, repo) do
    clock = Application.get_env(:singularity_workflow, :clock, Singularity.Workflow.Clock)

    dependency_records =
      Enum.flat_map(definition.dependencies, fn {step_name, deps} ->
        Enum.map(deps, fn dep_name ->
          %{
            run_id: run_id,
            step_slug: to_string(step_name),
            depends_on_step: to_string(dep_name),
            inserted_at: clock.now()
          }
        end)
      end)

    if dependency_records == [] do
      :ok
    else
      {_count, _} = repo.insert_all(StepDependency, dependency_records)
      :ok
    end
  end

  # Trace workflow structure for visualization
  @spec trace_workflow_structure(WorkflowDefinition.t(), Ecto.UUID.t()) :: :ok
  defp trace_workflow_structure(definition, run_id) do
    steps =
      Enum.map(definition.steps, fn {step_name, _step_fn} ->
        deps = Map.get(definition.dependencies, step_name, [])
        %{step_slug: to_string(step_name), depends_on: Enum.map(deps, &to_string/1)}
      end)

    dependencies =
      Enum.flat_map(definition.dependencies, fn {step_name, deps} ->
        Enum.map(deps, fn dep_name ->
          {to_string(step_name), to_string(dep_name)}
        end)
      end)

    FlowTracer.trace_workflow_structure(run_id, definition.slug, steps, dependencies)
    :ok
  end

  # Step 4: Ensure pgmq queue exists for this workflow
  @spec ensure_workflow_queue(String.t(), module()) :: :ok | {:error, term()}
  defp ensure_workflow_queue(workflow_slug, repo) do
    result =
      repo.query(
        "SELECT singularity_workflow.ensure_workflow_queue($1)",
        [workflow_slug]
      )

    case result do
      {:ok, _} ->
        Logger.debug("RunInitializer: Ensured queue exists", workflow_slug: workflow_slug)
        :ok

      {:error, reason} ->
        Logger.error("RunInitializer: Failed to ensure queue",
          workflow_slug: workflow_slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Step 5: Call start_ready_steps() to mark root steps as 'started' and send to pgmq
  # NOTE: start_ready_steps now creates task records AND sends messages to pgmq
  @spec start_ready_steps(Ecto.UUID.t(), module()) :: :ok | {:error, term()}
  defp start_ready_steps(run_id, repo) do
    # Convert string UUID to binary format for PostgreSQL
    {:ok, binary_run_id} = Ecto.UUID.dump(run_id)

    # Call PostgreSQL function via raw SQL
    result =
      repo.query(
        "SELECT * FROM start_ready_steps($1)",
        [binary_run_id]
      )

    case result do
      {:ok, %{rows: rows}} ->
        Logger.debug("RunInitializer: Started #{length(rows)} ready steps", run_id: run_id)
        :ok

      {:error, reason} ->
        Logger.error("RunInitializer: Failed to start ready steps",
          run_id: run_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
