defmodule Singularity.Workflow.OrchestratorNotifications do
  @moduledoc """
  HTDAG-specific notifications for singularity_workflow.

  Provides real-time event broadcasting for HTDAG workflows using PGMQ + NOTIFY.
  This enables event-driven coordination and monitoring of HTDAG execution.

  ## Features

  - **Decomposition Events**: Track goal decomposition progress
  - **Task Events**: Monitor individual task execution
  - **Workflow Events**: Track overall workflow progress
  - **Error Events**: Broadcast failures and recovery attempts
  - **Performance Events**: Track execution metrics and optimization

  ## Usage

      # Listen for HTDAG events
      {:ok, pid} = Singularity.Workflow.OrchestratorNotifications.listen("my_workflow", MyApp.Repo)
      
      # Handle events
      receive do
        {:htdag_event, ^pid, event_type, data} ->
          # Process HTDAG event
      end

  ## Event Types

  - `decomposition:started` - Goal decomposition began
  - `decomposition:completed` - Goal decomposition finished
  - `decomposition:failed` - Goal decomposition failed
  - `task:started` - Individual task started
  - `task:completed` - Individual task completed
  - `task:failed` - Individual task failed
  - `workflow:started` - Workflow execution began
  - `workflow:completed` - Workflow execution finished
  - `workflow:failed` - Workflow execution failed
  - `performance:metrics` - Performance metrics update

  ## AI Navigation Metadata

  ### Module Identity
  - **Type**: Notification Engine (supporting infrastructure)
  - **Purpose**: Real-time event broadcasting for orchestrator workflows
  - **Complements**: Singularity.Workflow.Orchestrator, Singularity.Workflow.OrchestratorOptimizer

  ### Call Graph
  - `listen/2` → `Singularity.Workflow.Notifications` (base notifications)
  - `broadcast_decomposition_event/4` → Singularity.Workflow.Notifications
  - `broadcast_task_event/4` → Singularity.Workflow.Notifications
  - `broadcast_workflow_event/4` → Singularity.Workflow.Notifications
  - **Integrates**: Notifications, Repository, OrchestratorOptimizer

  ### Anti-Patterns
  - ❌ DO NOT broadcast raw event data without structure - use event_type pattern
  - ❌ DO NOT block on notifications - use async broadcasting
  - ✅ DO publish all orchestrator lifecycle events
  - ✅ DO include workflow_id in all event data for traceability

  ### Search Keywords
  notifications, event_broadcasting, orchestrator_events, pgmq_notifications,
  real_time_monitoring, decomposition_events, task_tracking, workflow_monitoring,
  performance_metrics, event_driven_execution
  """

  require Logger

  @notifications_env_key :notifications_impl

  defp notifications_impl do
    Application.get_env(
      :singularity_workflow,
      @notifications_env_key,
      Singularity.Workflow.Notifications
    )
  end

  @doc """
  Broadcast HTDAG decomposition events.

  ## Parameters

  - `goal_id` - Unique identifier for the goal
  - `event` - Event type (:started, :completed, :failed)
  - `data` - Event-specific data
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, message_id}` - Event broadcast successfully
  - `{:error, reason}` - Broadcast failed

  ## Example

      Singularity.Workflow.OrchestratorNotifications.broadcast_decomposition(
        "goal-123",
        :started,
        %{goal: "Build auth system", timestamp: DateTime.utc_now()},
        MyApp.Repo
      )
  """
  @spec broadcast_decomposition(String.t(), atom(), map(), Ecto.Repo.t()) ::
          {:ok, String.t()} | {:error, any()}
  def broadcast_decomposition(goal_id, event, data, repo) do
    event_data = %{
      goal_id: goal_id,
      event: event,
      data: data,
      timestamp: DateTime.utc_now(),
      event_type: "decomposition"
    }

    notifications_impl().send_with_notify("htdag:decomposition", event_data, repo)
  end

  @doc """
  Broadcast task execution events.

  ## Parameters

  - `task_id` - Unique identifier for the task
  - `event` - Event type (:started, :completed, :failed)
  - `data` - Event-specific data
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, message_id}` - Event broadcast successfully
  - `{:error, reason}` - Broadcast failed

  ## Example

      Singularity.Workflow.OrchestratorNotifications.broadcast_task(
        "task-456",
        :completed,
        %{result: %{success: true}, duration: 1500},
        MyApp.Repo
      )
  """
  @spec broadcast_task(String.t(), atom(), map(), Ecto.Repo.t()) ::
          {:ok, String.t()} | {:error, any()}
  def broadcast_task(task_id, event, data, repo) do
    event_data = %{
      task_id: task_id,
      event: event,
      data: data,
      timestamp: DateTime.utc_now(),
      event_type: "task"
    }

    notifications_impl().send_with_notify("htdag:tasks", event_data, repo)
  end

  @doc """
  Broadcast workflow execution events.

  ## Parameters

  - `workflow_id` - Unique identifier for the workflow
  - `event` - Event type (:started, :completed, :failed)
  - `data` - Event-specific data
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, message_id}` - Event broadcast successfully
  - `{:error, reason}` - Broadcast failed
  """
  @spec broadcast_workflow(String.t(), atom(), map(), Ecto.Repo.t()) ::
          {:ok, String.t()} | {:error, any()}
  def broadcast_workflow(workflow_id, event, data, repo) do
    event_data = %{
      workflow_id: workflow_id,
      event: event,
      data: data,
      timestamp: DateTime.utc_now(),
      event_type: "workflow"
    }

    notifications_impl().send_with_notify("htdag:workflows", event_data, repo)
  end

  @doc """
  Broadcast performance metrics.

  ## Parameters

  - `workflow_id` - Workflow identifier
  - `metrics` - Performance metrics data
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, message_id}` - Metrics broadcast successfully
  - `{:error, reason}` - Broadcast failed
  """
  @spec broadcast_performance(String.t(), map(), Ecto.Repo.t()) ::
          {:ok, String.t()} | {:error, any()}
  def broadcast_performance(workflow_id, metrics, repo) do
    event_data = %{
      workflow_id: workflow_id,
      metrics: metrics,
      timestamp: DateTime.utc_now(),
      event_type: "performance"
    }

    notifications_impl().send_with_notify("htdag:performance", event_data, repo)
  end

  @doc """
  Listen for HTDAG events.

  ## Parameters

  - `workflow_name` - Name of the workflow to listen for (optional)
  - `repo` - Ecto repository
  - `opts` - Listen options
    - `:event_types` - List of event types to listen for (default: all)
    - `:timeout` - Listen timeout in milliseconds (default: :infinity)

  ## Returns

  - `{:ok, pid}` - Event listener process
  - `{:error, reason}` - Failed to start listener

  ## Example

      {:ok, pid} = Singularity.Workflow.OrchestratorNotifications.listen(
        "my_workflow",
        MyApp.Repo,
        event_types: [:decomposition, :task, :workflow]
      )
  """
  @spec listen(String.t() | nil, Ecto.Repo.t(), keyword()) :: {:ok, pid()} | {:error, any()}
  def listen(workflow_name \\ nil, repo, opts \\ []) do
    event_types = Keyword.get(opts, :event_types, [:decomposition, :task, :workflow, :performance])
    timeout = Keyword.get(opts, :timeout, :infinity)

    Logger.info("Starting HTDAG event listener for workflow: #{workflow_name || "all"}")

    # Start listener process
    pid = spawn_link(fn -> listen_loop(workflow_name, event_types, timeout, repo) end)
    {:ok, pid}
  end

  @doc """
  Stop listening for HTDAG events.

  ## Parameters

  - `pid` - Event listener process
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Stopped successfully
  - `{:error, reason}` - Stop failed
  """
  @spec stop_listening(pid(), Ecto.Repo.t()) :: :ok | {:error, any()}
  def stop_listening(pid, _repo) do
    Process.exit(pid, :normal)
    :ok
  end

  @doc """
  Get recent HTDAG events.

  ## Parameters

  - `event_type` - Type of events to retrieve (optional)
  - `limit` - Maximum number of events (default: 100)
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, events}` - List of recent events
  - `{:error, reason}` - Failed to retrieve events
  """
  @spec get_recent_events(atom() | nil, integer(), Ecto.Repo.t()) ::
          {:ok, list()} | {:error, any()}
  def get_recent_events(event_type \\ nil, limit \\ 100, repo) do
    if function_exported?(repo, :all, 1) do
      import Ecto.Query

      base_query =
        from(e in Singularity.Workflow.Orchestrator.Schemas.Event,
          order_by: [desc: e.timestamp],
          limit: ^limit,
          select: e
        )

      query =
        if event_type do
          from(e in base_query, where: e.event_type == ^to_string(event_type))
        else
          base_query
        end

      events = repo.all(query)

      formatted_events =
        Enum.map(events, fn event ->
          %{
            id: event.id,
            type: event.event_type,
            data: event.event_data,
            timestamp: event.timestamp,
            execution_id: event.execution_id,
            task_execution_id: event.task_execution_id
          }
        end)

      {:ok, formatted_events}
    else
      Logger.debug("Repository #{inspect(repo)} does not export all/1, returning empty event list")
      {:ok, []}
    end
  rescue
    error ->
      Logger.error("Failed to fetch recent events: #{inspect(error)}")
      {:error, error}
  end

  # Private functions

  defp listen_loop(workflow_name, event_types, timeout, repo) do
    # Listen for HTDAG events and forward to parent process
    receive do
      {:notification, _pid, channel, message_id} ->
        handle_notification(channel, message_id, workflow_name, event_types, repo)
        listen_loop(workflow_name, event_types, timeout, repo)

      :stop ->
        Logger.info("HTDAG event listener stopped")
        :ok

      other ->
        Logger.warning("Unexpected message in HTDAG listener: #{inspect(other)}")
        listen_loop(workflow_name, event_types, timeout, repo)
    after
      timeout ->
        Logger.info("HTDAG event listener timeout")
        :ok
    end
  end

  defp handle_notification(channel, message_id, _workflow_name, event_types, _repo) do
    # Handle incoming notifications
    # Parse channel to determine event type
    case channel do
      "pgmq_htdag:decomposition" ->
        if :decomposition in event_types do
          # Process decomposition event
          send_event(:decomposition, message_id)
        end

      "pgmq_htdag:tasks" ->
        if :task in event_types do
          # Process task event
          send_event(:task, message_id)
        end

      "pgmq_htdag:workflows" ->
        if :workflow in event_types do
          # Process workflow event
          send_event(:workflow, message_id)
        end

      "pgmq_htdag:performance" ->
        if :performance in event_types do
          # Process performance event
          send_event(:performance, message_id)
        end

      _ ->
        # Ignore other channels
        :ok
    end
  end

  defp send_event(event_type, message_id) do
    # Send event to parent process with message ID
    send(self(), {:htdag_event, self(), event_type, %{message_id: message_id}})
  end
end
