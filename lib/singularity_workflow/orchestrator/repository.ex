defmodule Singularity.Workflow.Orchestrator.Repository do
  @moduledoc """
  Repository functions for HTDAG data persistence.

  Provides database operations for HTDAG task graphs, workflows, executions,
  and related data structures.
  """

  require Logger
  import Ecto.Query
  alias Singularity.Workflow.Orchestrator.Schemas
  @behaviour Singularity.Workflow.Orchestrator.Repository.Behaviour

  @doc """
  Create a new task graph.

  ## Parameters

  - `attrs` - Task graph attributes
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, task_graph}` - Task graph created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_task_graph(map(), Ecto.Repo.t()) ::
          {:ok, Schemas.TaskGraph.t()} | {:error, Ecto.Changeset.t()}
  def create_task_graph(attrs, repo) do
    %Schemas.TaskGraph{}
    |> Schemas.TaskGraph.changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Get a task graph by ID.

  ## Parameters

  - `id` - Task graph ID
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, task_graph}` - Task graph found
  - `{:error, :not_found}` - Task graph not found
  """
  @spec get_task_graph(binary(), Ecto.Repo.t()) ::
          {:ok, Schemas.TaskGraph.t()} | {:error, :not_found}
  def get_task_graph(id, repo) do
    case repo.get(Schemas.TaskGraph, id) do
      nil -> {:error, :not_found}
      task_graph -> {:ok, task_graph}
    end
  end

  @doc """
  Create a new workflow.

  ## Parameters

  - `attrs` - Workflow attributes
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, workflow}` - Workflow created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_workflow(map(), Ecto.Repo.t()) ::
          {:ok, Schemas.Workflow.t()} | {:error, Ecto.Changeset.t()}
  def create_workflow(attrs, repo) do
    %Schemas.Workflow{}
    |> Schemas.Workflow.workflow_changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Get a workflow by ID.

  ## Parameters

  - `id` - Workflow ID
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, workflow}` - Workflow found
  - `{:error, :not_found}` - Workflow not found
  """
  @spec get_workflow(binary(), Ecto.Repo.t()) :: {:ok, Schemas.Workflow.t()} | {:error, :not_found}
  def get_workflow(id, repo) do
    case repo.get(Schemas.Workflow, id) do
      nil -> {:error, :not_found}
      workflow -> {:ok, workflow}
    end
  end

  @doc """
  Get workflows by name pattern.

  ## Parameters

  - `name_pattern` - Name pattern to search for
  - `repo` - Ecto repository
  - `opts` - Query options
    - `:limit` - Maximum number of results (default: 50)
    - `:offset` - Offset for pagination (default: 0)

  ## Returns

  - `{:ok, workflows}` - List of matching workflows
  - `{:error, reason}` - Query failed
  """
  @spec get_workflows_by_name(String.t(), Ecto.Repo.t(), keyword()) ::
          {:ok, list(Schemas.Workflow.t())} | {:error, any()}
  def get_workflows_by_name(name_pattern, repo, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(w in Schemas.Workflow,
        where: like(w.name, ^"%#{name_pattern}%"),
        limit: ^limit,
        offset: ^offset,
        order_by: [desc: w.created_at]
      )

    case repo.all(query) do
      workflows when is_list(workflows) -> {:ok, workflows}
      error -> {:error, error}
    end
  end

  @doc """
  Create a new execution.

  ## Parameters

  - `attrs` - Execution attributes
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, execution}` - Execution created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_execution(map(), Ecto.Repo.t()) ::
          {:ok, Schemas.Execution.t()} | {:error, Ecto.Changeset.t()}
  def create_execution(attrs, repo) do
    %Schemas.Execution{}
    |> Schemas.Execution.execution_changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Get an execution by ID.

  ## Parameters

  - `id` - Execution ID
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, execution}` - Execution found
  - `{:error, :not_found}` - Execution not found
  """
  @spec get_execution(binary(), Ecto.Repo.t()) ::
          {:ok, Schemas.Execution.t()} | {:error, :not_found}
  def get_execution(id, repo) do
    case repo.get(Schemas.Execution, id) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  end

  @doc """
  Update execution status.

  ## Parameters

  - `execution` - Execution to update
  - `status` - New status
  - `repo` - Ecto repository
  - `opts` - Update options
    - `:completed_at` - Completion timestamp
    - `:duration_ms` - Execution duration
    - `:result` - Execution result
    - `:error_message` - Error message if failed

  ## Returns

  - `{:ok, execution}` - Execution updated successfully
  - `{:error, changeset}` - Update failed
  """
  @spec update_execution_status(Schemas.Execution.t(), String.t(), Ecto.Repo.t(), keyword()) ::
          {:ok, Schemas.Execution.t()} | {:error, Ecto.Changeset.t()}
  def update_execution_status(execution, status, repo, opts \\ []) do
    attrs = %{
      status: status,
      completed_at: Keyword.get(opts, :completed_at),
      duration_ms: Keyword.get(opts, :duration_ms),
      result: Keyword.get(opts, :result),
      error_message: Keyword.get(opts, :error_message)
    }

    execution
    |> Schemas.Execution.execution_changeset(attrs)
    |> repo.update()
  end

  @doc """
  Create a task execution.

  ## Parameters

  - `attrs` - Task execution attributes
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, task_execution}` - Task execution created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_task_execution(map(), Ecto.Repo.t()) ::
          {:ok, Schemas.TaskExecution.t()} | {:error, Ecto.Changeset.t()}
  def create_task_execution(attrs, repo) do
    %Schemas.TaskExecution{}
    |> Schemas.TaskExecution.task_execution_changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Update task execution status.

  ## Parameters

  - `task_execution` - Task execution to update
  - `status` - New status
  - `repo` - Ecto repository
  - `opts` - Update options

  ## Returns

  - `{:ok, task_execution}` - Task execution updated successfully
  - `{:error, changeset}` - Update failed
  """
  @spec update_task_execution_status(
          Schemas.TaskExecution.t(),
          String.t(),
          Ecto.Repo.t(),
          keyword()
        ) ::
          {:ok, Schemas.TaskExecution.t()} | {:error, Ecto.Changeset.t()}
  def update_task_execution_status(task_execution, status, repo, opts \\ []) do
    attrs = %{
      status: status,
      started_at: Keyword.get(opts, :started_at),
      completed_at: Keyword.get(opts, :completed_at),
      duration_ms: Keyword.get(opts, :duration_ms),
      result: Keyword.get(opts, :result),
      error_message: Keyword.get(opts, :error_message),
      retry_count: Keyword.get(opts, :retry_count)
    }

    task_execution
    |> Schemas.TaskExecution.task_execution_changeset(attrs)
    |> repo.update()
  end

  @doc """
  Create an event.

  ## Parameters

  - `attrs` - Event attributes
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, event}` - Event created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_event(map(), Ecto.Repo.t()) ::
          {:ok, Schemas.Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(attrs, repo) do
    %Schemas.Event{}
    |> Schemas.Event.event_changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Get recent events for an execution.

  ## Parameters

  - `execution_id` - Execution ID
  - `repo` - Ecto repository
  - `opts` - Query options
    - `:limit` - Maximum number of events (default: 100)
    - `:event_types` - Filter by event types

  ## Returns

  - `{:ok, events}` - List of events
  - `{:error, reason}` - Query failed
  """
  @spec get_recent_events(binary(), Ecto.Repo.t(), keyword()) ::
          {:ok, list(Schemas.Event.t())} | {:error, any()}
  def get_recent_events(execution_id, repo, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    event_types = Keyword.get(opts, :event_types, [])

    query =
      from(e in Schemas.Event,
        where: e.execution_id == ^execution_id,
        limit: ^limit,
        order_by: [desc: e.timestamp]
      )

    query =
      if event_types != [] do
        from(e in query, where: e.event_type in ^event_types)
      else
        query
      end

    case repo.all(query) do
      events when is_list(events) -> {:ok, events}
      error -> {:error, error}
    end
  end

  @doc """
  Create a performance metric.

  ## Parameters

  - `attrs` - Performance metric attributes
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, metric}` - Metric created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_performance_metric(map(), Ecto.Repo.t()) ::
          {:ok, Schemas.PerformanceMetric.t()} | {:error, Ecto.Changeset.t()}
  def create_performance_metric(attrs, repo) do
    %Schemas.PerformanceMetric{}
    |> Schemas.PerformanceMetric.performance_metric_changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Get performance metrics for a workflow.

  ## Parameters

  - `workflow_id` - Workflow ID
  - `repo` - Ecto repository
  - `opts` - Query options
    - `:metric_type` - Filter by metric type
    - `:since` - Filter by timestamp
    - `:limit` - Maximum number of metrics

  ## Returns

  - `{:ok, metrics}` - List of performance metrics
  - `{:error, reason}` - Query failed
  """
  @spec get_performance_metrics(binary(), Ecto.Repo.t(), keyword()) ::
          {:ok, list(Schemas.PerformanceMetric.t())} | {:error, any()}
  def get_performance_metrics(workflow_id, repo, opts \\ []) do
    metric_type = Keyword.get(opts, :metric_type)
    since = Keyword.get(opts, :since)
    limit = Keyword.get(opts, :limit, 1000)

    query =
      from(m in Schemas.PerformanceMetric,
        where: m.workflow_id == ^workflow_id,
        limit: ^limit,
        order_by: [desc: m.timestamp]
      )

    query =
      if metric_type do
        from(m in query, where: m.metric_type == ^metric_type)
      else
        query
      end

    query =
      if since do
        from(m in query, where: m.timestamp >= ^since)
      else
        query
      end

    case repo.all(query) do
      metrics when is_list(metrics) -> {:ok, metrics}
      error -> {:error, error}
    end
  end

  @doc """
  Create a learning pattern.

  ## Parameters

  - `attrs` - Learning pattern attributes
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, pattern}` - Pattern created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_learning_pattern(map(), Ecto.Repo.t()) ::
          {:ok, Schemas.LearningPattern.t()} | {:error, Ecto.Changeset.t()}
  def create_learning_pattern(attrs, repo) do
    %Schemas.LearningPattern{}
    |> Schemas.LearningPattern.learning_pattern_changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Get learning patterns for a workflow.

  ## Parameters

  - `workflow_name` - Workflow name
  - `repo` - Ecto repository
  - `opts` - Query options
    - `:pattern_type` - Filter by pattern type
    - `:min_confidence` - Minimum confidence score

  ## Returns

  - `{:ok, patterns}` - List of learning patterns
  - `{:error, reason}` - Query failed
  """
  @spec get_learning_patterns(String.t(), Ecto.Repo.t(), keyword()) ::
          {:ok, list(Schemas.LearningPattern.t())} | {:error, any()}
  def get_learning_patterns(workflow_name, repo, opts \\ []) do
    pattern_type = Keyword.get(opts, :pattern_type)
    min_confidence = Keyword.get(opts, :min_confidence, 0.0)

    query =
      from(p in Schemas.LearningPattern,
        where: p.workflow_name == ^workflow_name and p.confidence_score >= ^min_confidence,
        order_by: [desc: p.confidence_score, desc: p.usage_count]
      )

    query =
      if pattern_type do
        from(p in query, where: p.pattern_type == ^pattern_type)
      else
        query
      end

    case repo.all(query) do
      patterns when is_list(patterns) -> {:ok, patterns}
      error -> {:error, error}
    end
  end

  @doc """
  Get execution statistics.

  ## Parameters

  - `repo` - Ecto repository
  - `opts` - Query options
    - `:workflow_id` - Filter by workflow ID
    - `:since` - Filter by start date
    - `:until` - Filter by end date

  ## Returns

  - `{:ok, stats}` - Execution statistics
  - `{:error, reason}` - Query failed
  """
  @spec get_execution_stats(Ecto.Repo.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get_execution_stats(repo, opts \\ []) do
    workflow_id = Keyword.get(opts, :workflow_id)
    since = Keyword.get(opts, :since)
    until = Keyword.get(opts, :until)

    base_query = from(e in Schemas.Execution)

    query =
      base_query
      |> maybe_filter_by_workflow(workflow_id)
      |> maybe_filter_by_date_range(since, until)

    case repo.aggregate(query, :count, :id) do
      total_executions when is_integer(total_executions) ->
        # Get success rate
        success_query = from(e in query, where: e.status == "completed")
        success_count = repo.aggregate(success_query, :count, :id) || 0

        # Get average duration
        avg_duration_query =
          from(e in query,
            where: not is_nil(e.duration_ms) and e.status == "completed"
          )

        avg_duration = repo.aggregate(avg_duration_query, :avg, :duration_ms) || 0

        stats = %{
          total_executions: total_executions,
          successful_executions: success_count,
          failed_executions: total_executions - success_count,
          success_rate: if(total_executions > 0, do: success_count / total_executions, else: 0.0),
          avg_duration_ms: avg_duration
        }

        {:ok, stats}

      error ->
        {:error, error}
    end
  end

  # Private functions

  defp maybe_filter_by_workflow(query, nil), do: query

  defp maybe_filter_by_workflow(query, workflow_id) do
    from(e in query, where: e.workflow_id == ^workflow_id)
  end

  defp maybe_filter_by_date_range(query, nil, nil), do: query

  defp maybe_filter_by_date_range(query, since, nil) do
    from(e in query, where: e.started_at >= ^since)
  end

  defp maybe_filter_by_date_range(query, nil, until) do
    from(e in query, where: e.started_at <= ^until)
  end

  defp maybe_filter_by_date_range(query, since, until) do
    from(e in query, where: e.started_at >= ^since and e.started_at <= ^until)
  end
end
