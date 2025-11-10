defmodule Singularity.Workflow.Lineage do
  @moduledoc """
  DAG-based lineage tracking for workflow execution history.

  Exposes workflow execution history for external learning systems.
  Each workflow run encodes:
  - Goal/input that triggered execution
  - Generated task graph (genotype)
  - Execution trace with full I/O (phenotype)
  - Performance metrics (fitness)

  Enables:
  - Deterministic replay
  - Generational learning
  - Pattern mining
  - Performance analysis
  """

  import Ecto.Query
  require Logger

  @doc """
  Get complete lineage for a workflow run.

  Returns execution history including:
  - Original goal/input
  - Task graph structure
  - Full execution trace with I/O
  - Performance metrics

  ## Example

      {:ok, lineage} = Singularity.Workflow.Lineage.get_lineage(run_id, repo)

      lineage.task_graph
      # => [%{id: "step1", depends_on: [], ...}, ...]

      lineage.execution_trace
      # => [%{step: "step1", input: ..., output: ..., duration_ms: 1234}, ...]

      lineage.metrics
      # => %{duration_ms: 5678, total_steps: 5, status: "completed"}
  """
  @spec get_lineage(run_id :: binary(), repo :: Ecto.Repo.t()) ::
          {:ok, map()} | {:error, term()}
  def get_lineage(run_id, repo) do
    # Get workflow run
    run = repo.get(Singularity.Workflow.WorkflowRun, run_id)

    if run do
      # Get all steps with their execution order
      steps =
        from(s in Singularity.Workflow.StepState,
          where: s.run_id == ^run_id,
          order_by: [asc: s.inserted_at],
          select: s
        )
        |> repo.all()

      # Get all tasks with full I/O
      tasks =
        from(t in Singularity.Workflow.StepTask,
          where: t.run_id == ^run_id,
          order_by: [asc: t.inserted_at],
          select: t
        )
        |> repo.all()

      # Get dependencies
      dependencies =
        from(d in Singularity.Workflow.StepDependency,
          where: d.run_id == ^run_id,
          select: d
        )
        |> repo.all()

      # Reconstruct task graph
      task_graph = build_task_graph(steps, dependencies)

      # Build execution trace
      execution_trace = build_trace(tasks)

      # Calculate metrics
      metrics = calculate_metrics(run, steps, tasks)

      lineage = %{
        run_id: run_id,
        goal: extract_goal(run.input),
        workflow_slug: run.workflow_slug,
        task_graph: task_graph,
        execution_trace: execution_trace,
        metrics: metrics,
        started_at: run.started_at,
        completed_at: run.completed_at,
        status: run.status
      }

      {:ok, lineage}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Replay a workflow from lineage (deterministic reproduction).

  Re-executes the same task graph with the same inputs to verify determinism.
  Uses idempotency keys to ensure reproducibility.

  ## Example

      {:ok, lineage} = Lineage.get_lineage(original_run_id, repo)
      {:ok, replay_run_id} = Lineage.replay(lineage, step_functions, repo)

      # Compare outcomes
      {:ok, replay_lineage} = Lineage.get_lineage(replay_run_id, repo)
      determinism = if lineage.metrics == replay_lineage.metrics, do: 1.0, else: 0.0
  """
  @spec replay(lineage :: map(), step_functions :: map(), repo :: Ecto.Repo.t()) ::
          {:ok, binary()} | {:error, term()}
  def replay(lineage, step_functions, repo) do
    Logger.info("Replaying workflow from lineage: #{lineage.run_id}")

    # Convert task graph back to Orchestrator format
    task_map = %{tasks: Map.values(lineage.task_graph)}

    case Singularity.Workflow.Orchestrator.create_workflow(
           task_map,
           step_functions,
           workflow_name: "replay_#{lineage.workflow_slug}"
         ) do
      {:ok, workflow} ->
        # Execute with original input
        input = %{goal: lineage.goal, replay_of: lineage.run_id}

        Singularity.Workflow.Orchestrator.Executor.execute_workflow(
          workflow,
          input,
          repo
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get lineage for multiple runs (batch query).

  Useful for analyzing patterns across executions.

  ## Example

      {:ok, lineages} = Lineage.get_lineages([run_id1, run_id2, run_id3], repo)
  """
  @spec get_lineages(run_ids :: list(binary()), repo :: Ecto.Repo.t()) ::
          {:ok, list(map())} | {:error, term()}
  def get_lineages(run_ids, repo) do
    lineages =
      Enum.map(run_ids, fn run_id ->
        case get_lineage(run_id, repo) do
          {:ok, lineage} -> lineage
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, lineages}
  end

  @doc """
  Query lineages by criteria.

  ## Options
  - `:status` - Filter by workflow status ("completed", "failed", "started")
  - `:since` - Filter by start date
  - `:until` - Filter by end date
  - `:workflow_slug` - Filter by workflow type
  - `:limit` - Maximum number of results

  ## Example

      {:ok, recent_successful} = Lineage.query_lineages(repo,
        status: "completed",
        since: DateTime.add(DateTime.utc_now(), -7, :day),
        limit: 100
      )
  """
  @spec query_lineages(repo :: Ecto.Repo.t(), opts :: keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def query_lineages(repo, opts \\ []) do
    query = from(r in Singularity.Workflow.WorkflowRun)

    # Apply filters
    query =
      if status = Keyword.get(opts, :status) do
        from(r in query, where: r.status == ^status)
      else
        query
      end

    query =
      if since = Keyword.get(opts, :since) do
        from(r in query, where: r.started_at >= ^since)
      else
        query
      end

    query =
      if until = Keyword.get(opts, :until) do
        from(r in query, where: r.started_at <= ^until)
      else
        query
      end

    query =
      if workflow_slug = Keyword.get(opts, :workflow_slug) do
        from(r in query, where: r.workflow_slug == ^workflow_slug)
      else
        query
      end

    # Apply limit and order
    limit = Keyword.get(opts, :limit, 100)

    query =
      from(r in query,
        order_by: [desc: r.started_at],
        limit: ^limit,
        select: r.id
      )

    run_ids = repo.all(query)
    get_lineages(run_ids, repo)
  end

  # Private functions

  defp build_task_graph(steps, dependencies) do
    # Convert StepState + StepDependency into task graph format
    Enum.into(steps, %{}, fn step ->
      deps =
        Enum.filter(dependencies, fn d -> d.step_slug == step.step_slug end)
        |> Enum.map(& &1.depends_on_step)

      task = %{
        id: step.step_slug,
        description: "Step: #{step.step_slug}",
        depends_on: deps,
        status: step.status,
        attempts: step.attempts_count,
        metadata: %{
          initial_tasks: step.initial_tasks,
          remaining_tasks: step.remaining_tasks
        }
      }

      {step.step_slug, task}
    end)
  end

  defp build_trace(tasks) do
    # Build execution trace from tasks
    Enum.map(tasks, fn task ->
      %{
        task_id: task.id,
        step_slug: task.step_slug,
        task_index: task.task_index,
        input: task.input,
        output: task.output,
        status: task.status,
        attempts: task.attempts_count,
        max_attempts: task.max_attempts,
        duration_ms: calculate_task_duration(task),
        idempotency_key: task.idempotency_key,
        started_at: task.inserted_at,
        completed_at: task.updated_at
      }
    end)
  end

  defp calculate_metrics(run, steps, tasks) do
    duration_ms =
      if run.completed_at do
        DateTime.diff(run.completed_at, run.started_at, :millisecond)
      else
        DateTime.diff(DateTime.utc_now(), run.started_at, :millisecond)
      end

    completed_steps = Enum.count(steps, &(&1.status == "completed"))
    failed_steps = Enum.count(steps, &(&1.status == "failed"))
    completed_tasks = Enum.count(tasks, &(&1.status == "completed"))
    failed_tasks = Enum.count(tasks, &(&1.status == "failed"))

    total_attempts = Enum.sum(Enum.map(tasks, & &1.attempts_count))

    %{
      duration_ms: duration_ms,
      total_steps: length(steps),
      completed_steps: completed_steps,
      failed_steps: failed_steps,
      total_tasks: length(tasks),
      completed_tasks: completed_tasks,
      failed_tasks: failed_tasks,
      total_attempts: total_attempts,
      status: run.status,
      error_message: run.error_message
    }
  end

  defp calculate_task_duration(task) do
    if task.updated_at && task.inserted_at do
      DateTime.diff(task.updated_at, task.inserted_at, :millisecond)
    else
      0
    end
  end

  defp extract_goal(input) when is_map(input) do
    # Try common goal field names
    input["goal"] || input[:goal] || input["description"] || input[:description] || input
  end

  defp extract_goal(input), do: input
end
