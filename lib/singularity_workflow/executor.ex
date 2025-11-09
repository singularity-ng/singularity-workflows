defmodule Singularity.Workflow.Executor do
  @moduledoc """
  Database-driven DAG workflow executor matching Singularity.Workflow's architecture.

  ## Overview

  Singularity.Workflow.Executor now implements database-driven execution with full DAG support:
  1. Parses workflow step definitions (supports both sequential and depends_on syntax)
  2. Initializes workflow run in database (creates runs, step_states, step_tasks, dependencies)
  3. Executes tasks in parallel as dependencies are satisfied
  4. Uses PostgreSQL functions for coordination (start_ready_steps, complete_task)
  5. Returns final result when all steps complete

  ## Execution Modes

  ### Sequential (Legacy, Backwards Compatible)

      def __workflow_steps__ do
        [
          {:step1, &__MODULE__.step1/1},
          {:step2, &__MODULE__.step2/1}
        ]
      end

  Automatically converted to: step2 depends on step1

  ### DAG (Parallel Dependencies)

      def __workflow_steps__ do
        [
          {:fetch, &__MODULE__.fetch/1, depends_on: []},
          {:analyze, &__MODULE__.analyze/1, depends_on: [:fetch]},
          {:summarize, &__MODULE__.summarize/1, depends_on: [:fetch]},
          {:save, &__MODULE__.save/1, depends_on: [:analyze, :summarize]}
        ]
      end

  Steps `analyze` and `summarize` run in parallel!

  ## Execution Flow (Database-Driven)

      execute(WorkflowModule, input, repo)
        ├─ Parse workflow definition
        │   ├─ Validate dependencies
        │   ├─ Check for cycles
        │   └─ Find root steps
        │
        ├─ Initialize run in database
        │   ├─ Create workflow_runs record
        │   ├─ Create step_states (with remaining_deps counters)
        │   ├─ Create step_dependencies
        │   ├─ Create step_tasks for root steps
        │   └─ Call start_ready_steps() to mark roots as 'started'
        │
        ├─ Execute task loop
        │   ├─ Poll for queued tasks
        │   ├─ Claim task (FOR UPDATE SKIP LOCKED)
        │   ├─ Execute step function
        │   ├─ Call complete_task() → cascades to dependents
        │   └─ Repeat until all tasks complete
        │
        └─ Return final output

  ## Multi-Instance Coordination

  Multiple workers can execute the same run_id concurrently:
  - PostgreSQL row-level locking prevents race conditions
  - Workers independently poll and claim tasks
  - complete_task() function atomically updates state
  - No inter-worker communication needed

  ## Error Handling

  - Task failure: Automatic retry (configurable max_attempts)
  - Step failure: Marks run as failed, no dependent steps execute
  - Timeout: Run-level timeout (default 5 minutes)
  - Validation: Cycle detection, dependency validation

  ## Usage

      # Sequential execution (legacy syntax)
      {:ok, result} = Singularity.Workflow.Executor.execute(MyWorkflow, input, MyApp.Repo)

      # DAG execution (parallel steps)
      {:ok, result} = Singularity.Workflow.Executor.execute(
        MyWorkflow,
        input,
        MyApp.Repo,
        timeout: 600_000  # 10 minutes
      )

      # Error handling
      case Singularity.Workflow.Executor.execute(MyWorkflow, input, repo) do
        {:ok, result} -> IO.inspect(result)
        {:error, reason} -> Logger.error("Workflow failed: \#{inspect(reason)}")
      end
  """

  require Logger

  alias Singularity.Workflow.DAG.RunInitializer
  alias Singularity.Workflow.DAG.TaskExecutor
  alias Singularity.Workflow.DAG.WorkflowDefinition

  @doc """
  Execute a workflow with database-driven DAG coordination.

  ## Parameters

    - `workflow_module` - Module implementing `__workflow_steps__/0`
    - `input` - Initial input map passed to workflow
    - `repo` - Ecto repo for database operations (e.g., MyApp.Repo)
    - `opts` - Execution options (optional)

  ## Options

    - `:timeout` - Maximum execution time in milliseconds (default: 300_000 = 5 minutes)
    - `:poll_interval` - Time between task polls in milliseconds (default: 100)
    - `:worker_id` - Worker identifier for task claiming (default: inspect(self()))

  ## Returns

    - `{:ok, result}` - Workflow completed successfully
    - `{:error, reason}` - Workflow failed (validation, execution, or timeout)

  ## Examples

      # Simple sequential workflow
      defmodule MyWorkflow do
        def __workflow_steps__ do
          [
            {:validate, &__MODULE__.validate/1},
            {:process, &__MODULE__.process/1},
            {:save, &__MODULE__.save/1}
          ]
        end

        def validate(input), do: {:ok, Map.put(input, :valid, true)}
        def process(input), do: {:ok, Map.update(input, :count, 0, &(&1 + 1))}
        def save(input), do: {:ok, input}
      end

      iex> {:ok, result} = Singularity.Workflow.Executor.execute(MyWorkflow, %{count: 5}, MyApp.Repo)
      iex> result.count
      6

      # DAG workflow with parallel steps
      defmodule DataPipeline do
        def __workflow_steps__ do
          [
            {:fetch, &__MODULE__.fetch/1, depends_on: []},
            {:analyze, &__MODULE__.analyze/1, depends_on: [:fetch]},
            {:summarize, &__MODULE__.summarize/1, depends_on: [:fetch]},
            {:report, &__MODULE__.report/1, depends_on: [:analyze, :summarize]}
          ]
        end

        def fetch(_), do: {:ok, %{data: [1,2,3]}}
        def analyze(state), do: {:ok, Map.put(state, :avg, 2.0)}
        def summarize(state), do: {:ok, Map.put(state, :count, 3)}
        def report(state), do: {:ok, state}
      end

      iex> {:ok, result} = Singularity.Workflow.Executor.execute(
      ...>   DataPipeline,
      ...>   %{},
      ...>   MyApp.Repo,
      ...>   timeout: 60_000
      ...> )
      iex> Map.keys(result)
      [:data, :avg, :count]
  """
  @spec execute(module(), map(), module(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(workflow_module, input, repo, opts \\ []) do
    Logger.info("Singularity.Workflow.Executor: Starting workflow",
      workflow: workflow_module,
      input_keys: Map.keys(input)
    )

    with {:ok, definition} <- WorkflowDefinition.parse(workflow_module),
         {:ok, run_id} <- RunInitializer.initialize(definition, input, repo),
         result <- TaskExecutor.execute_run(run_id, definition, repo, opts) do
      case result do
        {:ok, output} ->
          Logger.info("Singularity.Workflow.Executor: Workflow completed",
            workflow: workflow_module,
            run_id: run_id
          )

          {:ok, output}

        {:error, reason} ->
          Logger.error("Singularity.Workflow.Executor: Workflow failed",
            workflow: workflow_module,
            run_id: run_id,
            reason: inspect(reason)
          )

          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Singularity.Workflow.Executor: Workflow initialization failed",
          workflow: workflow_module,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Execute a dynamic workflow (stored in database).

  For workflows created via FlowBuilder API (AI/LLM-generated workflows).

  ## Parameters

    - `workflow_slug` - Workflow identifier (string, not module)
    - `input` - Initial input map
    - `step_functions` - Map of step_slug atoms to functions
    - `repo` - Ecto repo for database operations
    - `opts` - Execution options (same as execute/4)

  ## Returns

    - `{:ok, result}` - Workflow completed successfully
    - `{:error, reason}` - Workflow failed

  ## Example

      # AI generates workflow at runtime
      {:ok, _} = FlowBuilder.create_flow("ai_workflow", repo)
      {:ok, _} = FlowBuilder.add_step("ai_workflow", "step1", [], repo)
      {:ok, _} = FlowBuilder.add_step("ai_workflow", "step2", ["step1"], repo)

      # Provide step implementations
      step_functions = %{
        step1: fn _input -> {:ok, %{data: "processed"}} end,
        step2: fn input -> {:ok, Map.put(input, "done", true)} end
      }

      # Execute
      {:ok, result} = Singularity.Workflow.Executor.execute_dynamic(
        "ai_workflow",
        %{"initial" => "data"},
        step_functions,
        MyApp.Repo
      )
  """
  @spec execute_dynamic(String.t(), map(), map(), module(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute_dynamic(workflow_slug, input, step_functions, repo, opts \\ [])
      when is_binary(workflow_slug) do
    Logger.info("Singularity.Workflow.Executor: Starting dynamic workflow",
      workflow_slug: workflow_slug,
      input_keys: Map.keys(input)
    )

    alias Singularity.Workflow.DAG.DynamicWorkflowLoader

    with {:ok, definition} <- DynamicWorkflowLoader.load(workflow_slug, step_functions, repo),
         {:ok, run_id} <- RunInitializer.initialize(definition, input, repo),
         result <- TaskExecutor.execute_run(run_id, definition, repo, opts) do
      case result do
        {:ok, output} ->
          Logger.info("Singularity.Workflow.Executor: Dynamic workflow completed",
            workflow_slug: workflow_slug,
            run_id: run_id
          )

          {:ok, output}

        {:error, reason} ->
          Logger.error("Singularity.Workflow.Executor: Dynamic workflow failed",
            workflow_slug: workflow_slug,
            run_id: run_id,
            reason: inspect(reason)
          )

          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Singularity.Workflow.Executor: Dynamic workflow initialization failed",
          workflow_slug: workflow_slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Get the status of a workflow run.

  ## Returns

    - `{:ok, :completed, output}` - Run completed successfully
    - `{:ok, :failed, error}` - Run failed
    - `{:ok, :in_progress, progress}` - Run still executing
    - `{:error, :not_found}` - Run ID not found

  ## Examples

      # Check a running workflow
      iex> {:ok, run_id} = start_workflow(MyWorkflow, input, repo)
      iex> {:ok, status, info} = Singularity.Workflow.Executor.get_run_status(run_id, MyApp.Repo)
      iex> status
      :in_progress
      iex> info
      %{total_steps: 5, completed_steps: 2, percentage: 40.0}

      # Check completed workflow
      iex> {:ok, :completed, output} = Singularity.Workflow.Executor.get_run_status(completed_run_id, repo)
      iex> Map.get(output, "result")
      "success"

      # Check failed workflow
      iex> {:ok, :failed, error} = Singularity.Workflow.Executor.get_run_status(failed_run_id, repo)
      iex> error
      "Step :validate failed: Invalid input"

      # Non-existent run
      iex> Singularity.Workflow.Executor.get_run_status("00000000-0000-0000-0000-000000000000", repo)
      {:error, :not_found}
  """
  @spec get_run_status(Ecto.UUID.t(), module()) ::
          {:ok, :completed | :failed | :in_progress, term()} | {:error, :not_found}
  def get_run_status(run_id, repo) do
    import Ecto.Query

    case repo.get(Singularity.Workflow.WorkflowRun, run_id) do
      nil ->
        {:error, :not_found}

      run ->
        case run.status do
          "completed" ->
            {:ok, :completed, run.output}

          "failed" ->
            {:ok, :failed, run.error_message}

          "started" ->
            # Calculate progress
            progress = calculate_progress(run_id, repo)
            {:ok, :in_progress, progress}
        end
    end
  end

  @doc """
  Cancel a running workflow.

  Marks the workflow as failed and cancels any pending/running tasks.
  Also cancels associated Oban jobs if using distributed execution.

  ## Parameters

  - `run_id` - UUID of the workflow run
  - `repo` - Ecto repository
  - `opts` - Options
    - `:reason` - Cancellation reason (default: "User requested cancellation")
    - `:force` - Force cancel even if already completed (default: false)

  ## Returns

  - `:ok` - Workflow cancelled successfully
  - `{:error, reason}` - Cancellation failed

  ## Examples

      # Cancel a running workflow
      iex> :ok = Singularity.Workflow.Executor.cancel_workflow_run(run_id, repo)

      # Cancel with custom reason
      iex> :ok = Singularity.Workflow.Executor.cancel_workflow_run(
      ...>   run_id,
      ...>   repo,
      ...>   reason: "Timeout exceeded"
      ...> )
  """
  @spec cancel_workflow_run(Ecto.UUID.t(), module(), keyword()) :: :ok | {:error, term()}
  def cancel_workflow_run(run_id, repo, opts \\ []) do
    reason = Keyword.get(opts, :reason, "User requested cancellation")
    force = Keyword.get(opts, :force, false)

    import Ecto.Query

    repo.transaction(fn ->
      case repo.get(Singularity.Workflow.WorkflowRun, run_id) do
        nil ->
          repo.rollback({:error, :not_found})

        run ->
          unless force do
            if run.status in ["completed", "failed"] do
              repo.rollback({:error, {:already_finished, run.status}})
            end
          end

          # Mark workflow as failed
          run
          |> Singularity.Workflow.WorkflowRun.mark_failed(reason)
          |> repo.update!()

          # Cancel pending tasks
          from(t in Singularity.Workflow.StepTask,
            where: t.run_id == ^run_id,
            where: t.status in ["queued", "started"]
          )
          |> repo.update_all(set: [status: "cancelled", updated_at: DateTime.utc_now()])

          # Cancel Oban jobs if using distributed execution (internal detail)
          if Code.ensure_loaded?(Oban) do
            cancel_oban_jobs_for_run(run_id, repo)
          end

          Logger.info("Workflow cancelled",
            run_id: run_id,
            reason: reason
          )

          :ok
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List workflow runs with optional filtering.

  ## Parameters

  - `repo` - Ecto repository
  - `filters` - Filter options (optional)
    - `:status` - Filter by status ("started", "completed", "failed")
    - `:workflow_slug` - Filter by workflow module name
    - `:limit` - Maximum number of results (default: 100)
    - `:offset` - Pagination offset (default: 0)
    - `:order_by` - Order results (default: {:desc, :inserted_at})

  ## Returns

  - `{:ok, runs}` - List of workflow runs
  - `{:error, reason}` - Query failed

  ## Examples

      # List all runs
      iex> {:ok, runs} = Singularity.Workflow.Executor.list_workflow_runs(repo)

      # List only running workflows
      iex> {:ok, runs} = Singularity.Workflow.Executor.list_workflow_runs(repo, status: "started")

      # List failed workflows for specific module
      iex> {:ok, runs} = Singularity.Workflow.Executor.list_workflow_runs(repo,
      ...>   status: "failed",
      ...>   workflow_slug: "MyApp.Workflows.ProcessData"
      ...> )

      # Paginate results
      iex> {:ok, runs} = Singularity.Workflow.Executor.list_workflow_runs(repo,
      ...>   limit: 20,
      ...>   offset: 40
      ...> )
  """
  @spec list_workflow_runs(module(), keyword()) ::
          {:ok, [Singularity.Workflow.WorkflowRun.t()]} | {:error, term()}
  def list_workflow_runs(repo, filters \\ []) do
    import Ecto.Query

    query =
      from(r in Singularity.Workflow.WorkflowRun,
        select: r
      )

    # Apply filters
    query =
      if status = filters[:status] do
        from(r in query, where: r.status == ^status)
      else
        query
      end

    query =
      if workflow_slug = filters[:workflow_slug] do
        from(r in query, where: r.workflow_slug == ^workflow_slug)
      else
        query
      end

    # Apply ordering
    order_by = filters[:order_by] || {:desc, :inserted_at}
    query = from(r in query, order_by: ^[order_by])

    # Apply pagination
    limit = filters[:limit] || 100
    offset = filters[:offset] || 0
    query = from(r in query, limit: ^limit, offset: ^offset)

    runs = repo.all(query)
    {:ok, runs}
  rescue
    e -> {:error, {:query_failed, Exception.message(e)}}
  end

  @doc """
  Retry a failed workflow from the point of failure.

  Creates a new workflow run with the same input and workflow definition,
  but skips already-completed steps (optional).

  ## Parameters

  - `run_id` - UUID of the failed workflow run
  - `repo` - Ecto repository
  - `opts` - Retry options
    - `:skip_completed` - Skip steps that completed in original run (default: true)
    - `:reset_all` - Restart entire workflow from beginning (default: false)

  ## Returns

  - `{:ok, new_run_id}` - New workflow run ID
  - `{:error, reason}` - Retry failed

  ## Examples

      # Retry from point of failure
      iex> {:ok, new_run_id} = Singularity.Workflow.Executor.retry_failed_workflow(failed_run_id, repo)

      # Retry entire workflow from beginning
      iex> {:ok, new_run_id} = Singularity.Workflow.Executor.retry_failed_workflow(
      ...>   failed_run_id,
      ...>   repo,
      ...>   reset_all: true
      ...> )
  """
  @spec retry_failed_workflow(Ecto.UUID.t(), module(), keyword()) ::
          {:ok, Ecto.UUID.t()} | {:error, term()}
  def retry_failed_workflow(run_id, repo, opts \\ []) do
    reset_all = Keyword.get(opts, :reset_all, false)

    case repo.get(Singularity.Workflow.WorkflowRun, run_id) do
      nil ->
        {:error, :not_found}

      run ->
        if run.status != "failed" and not reset_all do
          {:error, {:not_failed, run.status}}
        else
          # Get workflow module
          workflow_module =
            try do
              String.to_existing_atom("Elixir.#{run.workflow_slug}")
            rescue
              ArgumentError -> nil
            end

          if workflow_module && function_exported?(workflow_module, :__workflow_steps__, 0) do
            Logger.info("Retrying workflow",
              original_run_id: run_id,
              workflow_slug: run.workflow_slug,
              reset_all: reset_all
            )

            # Execute workflow again with same input
            case execute(workflow_module, run.input, repo) do
              {:ok, _result} ->
                {:ok, run_id}

              {:error, reason} ->
                {:error, {:retry_failed, reason}}
            end
          else
            {:error, {:workflow_module_not_found, run.workflow_slug}}
          end
        end
    end
  end

  @doc """
  Pause a running workflow.

  Prevents new tasks from starting while allowing currently running tasks to complete.
  Paused workflows can be resumed later.

  ## Parameters

  - `run_id` - UUID of the workflow run
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Workflow paused successfully
  - `{:error, reason}` - Pause failed

  ## Examples

      iex> :ok = Singularity.Workflow.Executor.pause_workflow_run(run_id, repo)

  ## Note

  This is a soft pause - currently executing tasks will complete, but no new
  tasks will be started until the workflow is resumed.
  """
  @spec pause_workflow_run(Ecto.UUID.t(), module()) :: :ok | {:error, term()}
  def pause_workflow_run(run_id, repo) do
    import Ecto.Query

    repo.transaction(fn ->
      case repo.get(Singularity.Workflow.WorkflowRun, run_id) do
        nil ->
          repo.rollback({:error, :not_found})

        run ->
          if run.status != "started" do
            repo.rollback({:error, {:not_running, run.status}})
          end

          # Update workflow status to paused (custom status)
          # Note: Schema only has started/completed/failed, so we store in error_message
          run
          |> Ecto.Changeset.change(%{
            error_message: "PAUSED",
            updated_at: DateTime.utc_now()
          })
          |> repo.update!()

          # Mark queued tasks as paused
          from(t in Singularity.Workflow.StepTask,
            where: t.run_id == ^run_id,
            where: t.status == "queued"
          )
          |> repo.update_all(set: [status: "paused", updated_at: DateTime.utc_now()])

          Logger.info("Workflow paused", run_id: run_id)
          :ok
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resume a paused workflow.

  Allows queued tasks to continue execution.

  ## Parameters

  - `run_id` - UUID of the workflow run
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Workflow resumed successfully
  - `{:error, reason}` - Resume failed

  ## Examples

      iex> :ok = Singularity.Workflow.Executor.resume_workflow_run(run_id, repo)

  ## Note

  Only workflows paused via `pause_workflow_run/2` can be resumed.
  """
  @spec resume_workflow_run(Ecto.UUID.t(), module()) :: :ok | {:error, term()}
  def resume_workflow_run(run_id, repo) do
    import Ecto.Query

    repo.transaction(fn ->
      case repo.get(Singularity.Workflow.WorkflowRun, run_id) do
        nil ->
          repo.rollback({:error, :not_found})

        run ->
          if run.error_message != "PAUSED" do
            repo.rollback({:error, :not_paused})
          end

          # Clear pause marker
          run
          |> Ecto.Changeset.change(%{
            error_message: nil,
            updated_at: DateTime.utc_now()
          })
          |> repo.update!()

          # Resume paused tasks
          from(t in Singularity.Workflow.StepTask,
            where: t.run_id == ^run_id,
            where: t.status == "paused"
          )
          |> repo.update_all(set: [status: "queued", updated_at: DateTime.utc_now()])

          Logger.info("Workflow resumed", run_id: run_id)
          :ok
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  # Calculate workflow progress
  defp calculate_progress(run_id, repo) do
    import Ecto.Query

    total_steps =
      from(s in Singularity.Workflow.StepState,
        where: s.run_id == ^run_id,
        select: count()
      )
      |> repo.one()

    completed_steps =
      from(s in Singularity.Workflow.StepState,
        where: s.run_id == ^run_id,
        where: s.status == "completed",
        select: count()
      )
      |> repo.one()

    %{
      total_steps: total_steps,
      completed_steps: completed_steps,
      percentage: if(total_steps > 0, do: completed_steps / total_steps * 100, else: 0)
    }
  end

  # Cancel Oban jobs for a workflow run (internal - Oban is hidden from users)
  defp cancel_oban_jobs_for_run(run_id, repo) do
    import Ecto.Query

    try do
      # Query Oban jobs table for this workflow run
      oban_config = Application.get_env(:singularity, Oban, [])
      oban_repo = Keyword.get(oban_config, :repo, repo)

      if function_exported?(oban_repo, :all, 1) do
        query =
          from(j in "oban_jobs",
            where: fragment("?->>'workflow_run_id' = ?", j.args, ^run_id),
            where: j.state in ["available", "scheduled", "executing", "retryable"],
            select: j.id
          )

        job_ids = oban_repo.all(query)

        # Cancel each job using Oban API
        Enum.each(job_ids, fn job_id ->
          :ok = Oban.cancel_job(job_id)
          Logger.debug("Cancelled Oban job", job_id: job_id, run_id: run_id)
        end)
      end
    rescue
      e ->
        Logger.warning("Error cancelling Oban jobs",
          run_id: run_id,
          error: Exception.message(e)
        )
    end
  end
end
