defmodule Singularity.Workflow.OrchestratorNotificationsTest do
  use ExUnit.Case, async: true

  alias Singularity.Workflow.OrchestratorNotifications

  setup do
    Singularity.Workflow.Test.MoxHelper.setup_mox()

    Application.put_env(
      :singularity_workflow,
      :notifications_impl,
      Singularity.Workflow.Notifications.Mock
    )

    Mox.set_mox_global()
    :ok
  end

  describe "broadcast_decomposition/4" do
    test "broadcasts decomposition events successfully" do
      Mox.stub(Singularity.Workflow.Notifications.Mock, :send_with_notify, fn queue, data, _repo ->
        assert queue == "htdag:decomposition"
        assert data.goal_id == "goal_123"
        assert data.event == :started
        assert data.event_type == "decomposition"
        assert is_struct(data.occurred_at, DateTime)
        {:ok, "message_123"}
      end)

      {:ok, message_id} =
        OrchestratorNotifications.broadcast_decomposition(
          "goal_123",
          :started,
          %{goal: "Build auth system"},
          :mock_repo
        )

      assert message_id == "message_123"
    end

    test "handles broadcast failures" do
      Mox.stub(Singularity.Workflow.Notifications.Mock, :send_with_notify, fn _, _, _ ->
        {:error, :network_error}
      end)

      {:error, :network_error} =
        OrchestratorNotifications.broadcast_decomposition(
          "goal_123",
          :started,
          %{goal: "Build auth system"},
          :mock_repo
        )
    end
  end

  describe "broadcast_task/4" do
    test "broadcasts task events successfully" do
      Mox.stub(Singularity.Workflow.Notifications.Mock, :send_with_notify, fn queue, data, _repo ->
        assert queue == "htdag:tasks"
        assert data.task_id == "task_456"
        assert data.event == :completed
        assert data.event_type == "task"
        {:ok, "message_456"}
      end)

      {:ok, message_id} =
        OrchestratorNotifications.broadcast_task(
          "task_456",
          :completed,
          %{result: %{success: true}},
          :mock_repo
        )

      assert message_id == "message_456"
    end
  end

  describe "broadcast_workflow/4" do
    test "broadcasts workflow events successfully" do
      Mox.stub(Singularity.Workflow.Notifications.Mock, :send_with_notify, fn queue, data, _repo ->
        assert queue == "htdag:workflows"
        assert data.workflow_id == "workflow_789"
        assert data.event == :started
        assert data.event_type == "workflow"
        {:ok, "message_789"}
      end)

      {:ok, message_id} =
        OrchestratorNotifications.broadcast_workflow(
          "workflow_789",
          :started,
          %{workflow_name: "test_workflow"},
          :mock_repo
        )

      assert message_id == "message_789"
    end
  end

  describe "broadcast_performance/3" do
    test "broadcasts performance metrics successfully" do
      Mox.stub(Singularity.Workflow.Notifications.Mock, :send_with_notify, fn queue, data, _repo ->
        # Focused assertions on critical fields
        assert queue == "htdag:performance"
        assert data.workflow_id == "workflow_789"
        assert data.event_type == "performance"
        assert data.metrics.execution_time == 1500

        # Snapshot the notification payload for structure regression detection
        Singularity.Workflow.Test.Snapshot.assert_snapshot(
          data,
          "orchestrator_notifications_performance"
        )

        {:ok, "message_perf"}
      end)

      {:ok, message_id} =
        OrchestratorNotifications.broadcast_performance(
          "workflow_789",
          %{execution_time: 1500, success_rate: 0.95},
          :mock_repo
        )

      assert message_id == "message_perf"
    end
  end

  describe "listen/3" do
    test "starts event listener successfully" do
      {:ok, pid} =
        OrchestratorNotifications.listen("test_workflow", :mock_repo,
          event_types: [:decomposition, :task]
        )

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "starts listener with all event types by default" do
      {:ok, pid} = OrchestratorNotifications.listen("test_workflow", :mock_repo)

      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end

  describe "stop_listening/2" do
    test "stops event listener successfully" do
      {:ok, pid} = OrchestratorNotifications.listen("test_workflow", :mock_repo)

      :ok = OrchestratorNotifications.stop_listening(pid, :mock_repo)

      # Process should be terminated
      refute Process.alive?(pid)
    end
  end

  describe "get_recent_events/3" do
    test "returns recent events" do
      {:ok, events} = OrchestratorNotifications.get_recent_events(:decomposition, 10, :mock_repo)

      assert is_list(events)
    end

    test "returns all events when no event type specified" do
      {:ok, events} = OrchestratorNotifications.get_recent_events(nil, 50, :mock_repo)

      assert is_list(events)
    end
  end
end
