defmodule Singularity.Workflow do
  @moduledoc """
  Singularity.Workflow - Complete workflow orchestration with self-improving capabilities.

  A unified package providing complete workflow orchestration capabilities,
  combining PGMQ-based message queuing, HTDAG goal decomposition, workflow execution,
  and real-time notifications. Includes workflow optimization features that learn and
  adapt from execution history via `Lineage` tracking and `OrchestratorOptimizer`.

  Converts high-level goals into executable task graphs with automatic dependency
  resolution and parallel execution. Workflows automatically improve over time
  through adaptive learning and optimization.

  ## Dynamic vs Static Workflows

  singularity_workflow supports TWO ways to define workflows:

  ### 1. Static (Code-Based) - Recommended for most use cases

  Define workflows as Elixir modules with `__workflow_steps__/0`:

      defmodule MyWorkflow do
        def __workflow_steps__ do
          [{:step1, &__MODULE__.step1/1, depends_on: []}]
        end
        def step1(input), do: {:ok, input}
      end

      Singularity.Workflow.Executor.execute(MyWorkflow, input, repo)

  ### 2. Dynamic (Database-Stored) - For AI/LLM generation

  Create workflows at runtime via FlowBuilder API:

      {:ok, _} = Singularity.Workflow.FlowBuilder.create_flow("ai_workflow", repo)
      {:ok, _} = Singularity.Workflow.FlowBuilder.add_step("ai_workflow", "step1", [], repo)

      step_functions = %{step1: fn input -> {:ok, input} end}
      Singularity.Workflow.Executor.execute_dynamic("ai_workflow", input, step_functions, repo)

  **Both approaches use the same execution engine!**

  ## HTDAG Integration

  Singularity.Workflow includes `Singularity.Workflow.HTDAG` for goal-driven workflow creation:

      # Define a decomposer function
      defmodule MyApp.GoalDecomposer do
        def decompose(goal) do
          # Your custom decomposition logic
          tasks = [
            %{id: "task1", description: "Analyze requirements", depends_on: []},
            %{id: "task2", description: "Design architecture", depends_on: ["task1"]},
            %{id: "task3", description: "Implement solution", depends_on: ["task2"]}
          ]
          {:ok, tasks}
        end
      end

      # Compose and execute workflow from goal
      {:ok, result} = Singularity.Workflow.WorkflowComposer.compose_from_goal(
        "Build user authentication system",
        &MyApp.GoalDecomposer.decompose/1,
        step_functions,
        MyApp.Repo
      )

  ## Real-time Notifications

  Singularity.Workflow includes `Singularity.Workflow.Notifications` for real-time message delivery:

      # Send message with real-time notification
      {:ok, message_id} = Singularity.Workflow.Notifications.send_with_notify(
        "chat_messages",
        %{type: "notification", content: "Hello!"},
        MyApp.Repo
      )

      # Listen for real-time updates
      {:ok, pid} = Singularity.Workflow.Notifications.listen("chat_messages", MyApp.Repo)

  ## Architecture

  singularity_workflow provides complete workflow orchestration with self-improving capabilities:

  - **pgmq Extension** - PostgreSQL Message Queue for task coordination
  - **Database-Driven** - Task state persisted in PostgreSQL tables
  - **DAG Syntax** - Define dependencies with `depends_on: [:step]`
  - **Parallel Execution** - Independent branches run concurrently
  - **Map Steps** - Variable task counts (`initial_tasks: N`) for bulk processing
  - **Dependency Merging** - Steps receive outputs from all dependencies
  - **Multi-Instance** - Horizontal scaling via pgmq + PostgreSQL
  - **Self-Improving Workflows** - Lineage tracking + OrchestratorOptimizer for adaptive learning

  ## Quick Start

  1. **Install pgmq extension:**

      psql> CREATE EXTENSION pgmq VERSION '1.4.4';

  2. **Define workflow:**

      defmodule MyApp.Workflows.ProcessData do
        def __workflow_steps__ do
          [
            # Root step
            {:fetch, &__MODULE__.fetch/1, depends_on: []},

            # Parallel branches
            {:analyze, &__MODULE__.analyze/1, depends_on: [:fetch]},
            {:summarize, &__MODULE__.summarize/1, depends_on: [:fetch]},

            # Convergence step
            {:save, &__MODULE__.save/1, depends_on: [:analyze, :summarize]}
          ]
        end

        def fetch(input) do
          {:ok, %{data: "fetched"}}
        end

        def analyze(state) do
          # Has access to fetch output
          {:ok, %{analysis: "done"}}
        end

        def summarize(state) do
          # Runs in parallel with analyze!
          {:ok, %{summary: "complete"}}
        end

        def save(state) do
          # Has access to analyze AND summarize outputs
          {:ok, state}
        end
      end

  3. **Execute workflow:**

      {:ok, result} = Singularity.Workflow.Executor.execute(
        MyApp.Workflows.ProcessData,
        %{"user_id" => 123},
        MyApp.Repo
      )

  ## Map Steps (Bulk Processing)

  Process multiple items in parallel:

      def __workflow_steps__ do
        [
          {:fetch_users, &__MODULE__.fetch_users/1, depends_on: []},

          # Create 50 parallel tasks!
          {:process_user, &__MODULE__.process_user/1,
           depends_on: [:fetch_users],
           initial_tasks: 50},

          {:aggregate, &__MODULE__.aggregate/1, depends_on: [:process_user]}
        ]
      end

  ## Self-Improving Workflows

  Singularity.Workflow includes automatic workflow optimization features:

  **Lineage Tracking** (`Singularity.Workflow.Lineage`):
  - Tracks complete execution history (genotype + phenotype + metrics)
  - Enables deterministic replay for verification
  - Provides pattern mining data for learning

  **OrchestratorOptimizer** (`Singularity.Workflow.OrchestratorOptimizer`):
  - Learns from execution patterns via lineage data
  - Automatically optimizes timeouts, retries, parallelization
  - Adapts resource allocation based on historical performance
  - Three optimization levels: `:basic`, `:advanced`, `:aggressive`

  **Example: Self-Improving Workflow**:
  ```elixir
  # Run workflow - will be tracked in lineage
  {:ok, result} = Singularity.Workflow.Executor.execute(MyWorkflow, input, repo)

  # On subsequent runs, OrchestratorOptimizer will automatically:
  # - Learn from previous execution patterns
  # - Adjust timeouts based on variance
  # - Reorder tasks for better parallelization
  # - Optimize resource allocation
  # → Each run gets progressively faster!
  ```

  ## Workflow Lifecycle Management

  Control running workflows with lifecycle management functions:

  ```elixir
  # Start a workflow
  {:ok, result, run_id} = Singularity.Workflow.Executor.execute(
    MyWorkflow,
    %{user_id: 123},
    MyApp.Repo
  )

  # Check status
  {:ok, :in_progress, %{total_steps: 5, completed_steps: 2}} =
    Singularity.Workflow.get_run_status(run_id, MyApp.Repo)

  # List all running workflows
  {:ok, runs} = Singularity.Workflow.list_workflow_runs(MyApp.Repo, status: "started")

  # Pause execution
  :ok = Singularity.Workflow.pause_workflow_run(run_id, MyApp.Repo)

  # Resume execution
  :ok = Singularity.Workflow.resume_workflow_run(run_id, MyApp.Repo)

  # Cancel workflow
  :ok = Singularity.Workflow.cancel_workflow_run(
    run_id,
    MyApp.Repo,
    reason: "User requested cancellation"
  )

  # Retry failed workflow
  {:ok, new_run_id} = Singularity.Workflow.retry_failed_workflow(
    failed_run_id,
    MyApp.Repo
  )
  ```

  ## Requirements

  - **PostgreSQL 12+**
  - **pgmq extension 1.4.4+** - `CREATE EXTENSION pgmq`
  - **Ecto & Postgrex** - For database access

  See `Singularity.Workflow.Executor` for execution options and `Singularity.Workflow.DAG.WorkflowDefinition`
  for workflow syntax details.

  ## Real-time Messaging

  singularity_workflow provides complete messaging infrastructure via PostgreSQL NOTIFY (NATS replacement):

      # Send workflow message with NOTIFY
      {:ok, message_id} = Singularity.Workflow.Notifications.send_with_notify(
        "workflow_events",
        %{type: "task_completed", task_id: "123"},
        MyApp.Repo
      )

      # Listen for real-time workflow messages
      {:ok, pid} = Singularity.Workflow.Notifications.listen("workflow_events", MyApp.Repo)

      # All messages are automatically logged with structured data:
      # - Channel names, message IDs, timing, message types
      # - Success/error logging with context
      # - Performance metrics and debugging information

  ### Message Types

  | Event Type | Description | Payload |
  |------------|-------------|---------|
  | `workflow_started` | Workflow execution begins | `{workflow_id, input}` |
  | `task_started` | Individual task starts | `{task_id, workflow_id, step_name}` |
  | `task_completed` | Task finishes successfully | `{task_id, result, duration_ms}` |
  | `task_failed` | Task fails with error | `{task_id, error, retry_count}` |
  | `workflow_completed` | Entire workflow finishes | `{workflow_id, final_result}` |
  | `workflow_failed` | Workflow fails | `{workflow_id, error, failed_task}` |

  ### Integration Examples

      # Observer Web UI integration
      {:ok, _} = Singularity.Workflow.Notifications.send_with_notify("observer_approvals", %{
        type: "approval_created",
        approval_id: "app_123",
        title: "Deploy to Production"
      }, MyApp.Repo)

      # CentralCloud pattern learning
      {:ok, _} = Singularity.Workflow.Notifications.send_with_notify("centralcloud_patterns", %{
        type: "pattern_learned",
        pattern_type: "microservice_architecture",
        confidence_score: 0.95
      }, MyApp.Repo)

      # Genesis autonomous learning
      {:ok, _} = Singularity.Workflow.Notifications.send_with_notify("genesis_learning", %{
        type: "rule_evolved",
        rule_type: "optimization",
        improvement: 0.12
      }, MyApp.Repo)

  ## Orchestrator Integration

  singularity_workflow includes `Singularity.Workflow.Orchestrator` for goal-driven workflow creation:

      # Define a decomposer function
      defmodule MyApp.GoalDecomposer do
        def decompose(goal) do
          # Your custom decomposition logic
          tasks = [
            %{id: "task1", description: "Analyze requirements", depends_on: []},
            %{id: "task2", description: "Design architecture", depends_on: ["task1"]},
            %{id: "task3", description: "Implement solution", depends_on: ["task2"]}
          ]
          {:ok, tasks}
        end
      end

      # Compose and execute workflow from goal
      {:ok, result} = Singularity.Workflow.WorkflowComposer.compose_from_goal(
        "Build user authentication system",
        &MyApp.GoalDecomposer.decompose/1,
        step_functions,
        MyApp.Repo
      )
  """

  # Messaging functions (PostgreSQL NOTIFY - NATS replacement)
  defdelegate send_with_notify(queue, message, repo), to: Singularity.Workflow.Notifications
  defdelegate listen(queue, repo), to: Singularity.Workflow.Notifications
  defdelegate unlisten(listener_pid, repo), to: Singularity.Workflow.Notifications
  defdelegate notify_only(channel, payload, repo), to: Singularity.Workflow.Notifications

  # Workflow lifecycle management functions
  defdelegate cancel_workflow_run(run_id, repo, opts \\ []), to: Singularity.Workflow.Executor
  defdelegate list_workflow_runs(repo, filters \\ []), to: Singularity.Workflow.Executor
  defdelegate retry_failed_workflow(run_id, repo, opts \\ []), to: Singularity.Workflow.Executor
  defdelegate pause_workflow_run(run_id, repo), to: Singularity.Workflow.Executor
  defdelegate resume_workflow_run(run_id, repo), to: Singularity.Workflow.Executor
  defdelegate get_run_status(run_id, repo), to: Singularity.Workflow.Executor

  @doc """
  Returns the current version of singularity_workflow.

  ## Examples

      iex> Singularity.Workflow.version()
      "0.1.5"
  """
  @spec version() :: String.t()
  def version, do: "0.1.5"
end
