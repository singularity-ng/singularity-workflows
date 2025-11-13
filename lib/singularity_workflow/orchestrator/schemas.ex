defmodule Singularity.Workflow.Orchestrator.Schemas do
  @moduledoc """
  Ecto schemas for HTDAG orchestrator functionality.

  These schemas support goal-driven workflow decomposition and execution tracking.
  """

  defmodule TaskGraph do
    @moduledoc """
    Schema for hierarchical task graphs in HTDAG orchestration.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            id: binary(),
            name: String.t(),
            goal: String.t(),
            decomposer_module: String.t(),
            task_graph: map(),
            metadata: map(),
            max_depth: integer(),
            status: String.t(),
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    @statuses ~w(pending ready active completed failed cancelled)

    schema "orchestrator_task_graphs" do
      field(:name, :string)
      field(:goal, :string)
      field(:decomposer_module, :string)
      field(:task_graph, :map)
      field(:metadata, :map, default: %{})
      field(:max_depth, :integer, default: 5)
      field(:status, :string, default: "pending")
      timestamps()
    end

    def changeset(task_graph, attrs) do
      task_graph
      |> cast(attrs, [:name, :goal, :decomposer_module, :task_graph, :metadata, :max_depth, :status])
      |> validate_required([:name, :goal, :decomposer_module, :task_graph])
      |> validate_number(:max_depth, greater_than: 0, less_than: 20)
      |> validate_inclusion(:status, @statuses)
    end
  end

  defmodule Workflow do
    @moduledoc """
    Schema for workflow metadata.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            id: binary(),
            name: String.t(),
            description: String.t() | nil,
            workflow_definition: map(),
            step_functions: map(),
            config: map(),
            metadata: map(),
            max_parallel: non_neg_integer(),
            retry_attempts: non_neg_integer(),
            status: String.t(),
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    @statuses ~w(created running completed failed cancelled)

    schema "orchestrator_workflows" do
      field(:name, :string)
      field(:description, :string)
      field(:workflow_definition, :map)
      field(:step_functions, :map)
      field(:config, :map, default: %{})
      field(:metadata, :map, default: %{})
      field(:max_parallel, :integer, default: 1)
      field(:retry_attempts, :integer, default: 0)
      field(:status, :string, default: "created")
      timestamps()
    end

    def workflow_changeset(workflow, attrs) do
      workflow
      |> cast(attrs, [
        :name,
        :description,
        :workflow_definition,
        :step_functions,
        :config,
        :metadata,
        :max_parallel,
        :retry_attempts,
        :status
      ])
      |> validate_required([:name, :workflow_definition, :step_functions])
      |> validate_number(:max_parallel, greater_than: 0)
      |> validate_number(:retry_attempts, greater_than_or_equal_to: 0)
      |> validate_inclusion(:status, @statuses)
    end
  end

  defmodule Execution do
    @moduledoc """
    Schema for workflow executions.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            id: binary(),
            workflow_id: binary(),
            status: String.t(),
            result: map() | nil,
            started_at: DateTime.t() | nil,
            completed_at: DateTime.t() | nil,
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    @statuses ~w(pending running completed failed cancelled)

    schema "orchestrator_executions" do
      field(:execution_id, :string)
      field(:workflow_id, :binary_id)
      field(:goal_context, :map, default: %{})
      field(:status, :string, default: "pending")
      field(:result, :map, default: %{})
      field(:error_message, :string)
      field(:duration_ms, :integer)
      field(:started_at, :utc_datetime)
      field(:completed_at, :utc_datetime)
      timestamps()
    end

    def execution_changeset(execution, attrs) do
      execution
      |> cast(attrs, [
        :execution_id,
        :workflow_id,
        :goal_context,
        :status,
        :result,
        :error_message,
        :duration_ms,
        :started_at,
        :completed_at
      ])
      |> validate_required([:execution_id, :goal_context, :status])
      |> validate_inclusion(:status, @statuses)
    end
  end

  defmodule TaskExecution do
    @moduledoc """
    Schema for task executions.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            id: binary(),
            execution_id: binary(),
            task_id: String.t(),
            status: String.t(),
            result: map() | nil,
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    @statuses ~w(pending running completed failed cancelled)

    schema "orchestrator_task_executions" do
      field(:execution_id, :binary_id)
      field(:task_id, :string)
      field(:task_name, :string)
      field(:status, :string, default: "pending")
      field(:retry_count, :integer, default: 0)
      field(:result, :map, default: %{})
      field(:error_message, :string)
      field(:duration_ms, :integer)
      field(:started_at, :utc_datetime)
      field(:completed_at, :utc_datetime)
      timestamps()
    end

    def task_execution_changeset(task_execution, attrs) do
      task_execution
      |> cast(attrs, [
        :execution_id,
        :task_id,
        :task_name,
        :status,
        :retry_count,
        :result,
        :error_message,
        :duration_ms,
        :started_at,
        :completed_at
      ])
      |> validate_required([:execution_id, :task_id, :task_name, :status])
      |> validate_number(:retry_count, greater_than_or_equal_to: 0, less_than: 10)
      |> validate_inclusion(:status, @statuses)
    end
  end

  defmodule Event do
    @moduledoc """
    Schema for orchestrator events.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            id: binary(),
            event_type: String.t(),
            event_data: map() | nil,
            occurred_at: DateTime.t() | nil,
            execution_id: binary() | nil,
            task_execution_id: binary() | nil,
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    @allowed_event_types [
      "task:started",
      "task:completed",
      "task:failed",
      "workflow:started",
      "workflow:completed",
      "workflow:failed",
      "decomposition:started",
      "decomposition:completed",
      "decomposition:failed",
      "performance",
      "performance:metrics"
    ]

    schema "orchestrator_events" do
      field(:event_type, :string)
      field(:event_data, :map, default: %{})
      field(:occurred_at, :utc_datetime)
      field(:execution_id, :binary_id)
      field(:task_execution_id, :binary_id)
      timestamps()
    end

    def event_changeset(event, attrs) do
      event
      |> cast(attrs, [:event_type, :event_data, :occurred_at, :execution_id, :task_execution_id])
      |> validate_required([:event_type, :event_data])
      |> validate_change(:event_type, fn :event_type, value ->
        if valid_event_type?(value) do
          []
        else
          [event_type: "is invalid"]
        end
      end)
    end

    defp valid_event_type?(value) when value in @allowed_event_types, do: true

    defp valid_event_type?(value),
      do: String.match?(value, ~r/^[a-z_]+:(started|completed|failed)$/)
  end

  defmodule PerformanceMetric do
    @moduledoc """
    Schema for performance metrics.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            id: binary(),
            workflow_id: binary(),
            task_id: String.t(),
            metric_type: String.t(),
            metric_value: float(),
            metric_unit: String.t() | nil,
            context: map(),
            recorded_at: DateTime.t() | nil,
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    @metric_types ["execution_time", "success_rate", "error_rate", "throughput", "latency"]

    schema "orchestrator_performance_metrics" do
      field(:workflow_id, :binary_id)
      field(:task_id, :string)
      field(:metric_type, :string)
      field(:metric_value, :float)
      field(:metric_unit, :string)
      field(:context, :map, default: %{})
      field(:recorded_at, :utc_datetime)
      timestamps()
    end

    def performance_metric_changeset(metric, attrs) do
      metric
      |> cast(attrs, [
        :workflow_id,
        :task_id,
        :metric_type,
        :metric_value,
        :metric_unit,
        :context,
        :recorded_at
      ])
      |> validate_required([:workflow_id, :metric_type, :metric_value])
      |> validate_number(:metric_value, greater_than_or_equal_to: 0)
      |> validate_inclusion(:metric_type, @metric_types)
    end
  end

  defmodule LearningPattern do
    @moduledoc """
    Schema for learned optimization patterns.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            id: binary(),
            workflow_name: String.t(),
            pattern_type: String.t(),
            pattern_data: map(),
            confidence_score: float(),
            usage_count: integer(),
            last_used_at: DateTime.t() | nil,
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    @pattern_types ["parallelization", "decomposition", "retry_strategy", "resource_allocation"]

    schema "orchestrator_learning_patterns" do
      field(:workflow_name, :string)
      field(:pattern_type, :string)
      field(:pattern_data, :map)
      field(:confidence_score, :float, default: 0.0)
      field(:usage_count, :integer, default: 0)
      field(:last_used_at, :utc_datetime)
      timestamps()
    end

    def learning_pattern_changeset(pattern, attrs) do
      pattern
      |> cast(attrs, [
        :workflow_name,
        :pattern_type,
        :pattern_data,
        :confidence_score,
        :usage_count,
        :last_used_at
      ])
      |> validate_required([:workflow_name, :pattern_type, :pattern_data])
      |> validate_number(:confidence_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
      |> validate_number(:usage_count, greater_than_or_equal_to: 0)
      |> validate_inclusion(:pattern_type, @pattern_types)
    end
  end
end
