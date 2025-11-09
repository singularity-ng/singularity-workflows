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
            goal: String.t(),
            tasks: map(),
            metadata: map(),
            status: String.t(),
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "orchestrator_task_graphs" do
      field(:goal, :string)
      field(:tasks, :map)
      field(:metadata, :map, default: %{})
      field(:status, :string, default: "pending")
      timestamps()
    end

    def changeset(task_graph, attrs) do
      task_graph
      |> cast(attrs, [:goal, :tasks, :metadata, :status])
      |> validate_required([:goal])
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
            config: map(),
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "orchestrator_workflows" do
      field(:name, :string)
      field(:description, :string)
      field(:config, :map, default: %{})
      timestamps()
    end

    def workflow_changeset(workflow, attrs) do
      workflow
      |> cast(attrs, [:name, :description, :config])
      |> validate_required([:name])
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
    schema "orchestrator_executions" do
      field(:workflow_id, :binary_id)
      field(:status, :string)
      field(:result, :map)
      field(:started_at, :utc_datetime)
      field(:completed_at, :utc_datetime)
      timestamps()
    end

    def execution_changeset(execution, attrs) do
      execution
      |> cast(attrs, [:workflow_id, :status, :result, :started_at, :completed_at])
      |> validate_required([:workflow_id, :status])
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
    schema "orchestrator_task_executions" do
      field(:execution_id, :binary_id)
      field(:task_id, :string)
      field(:status, :string)
      field(:result, :map)
      timestamps()
    end

    def task_execution_changeset(task_execution, attrs) do
      task_execution
      |> cast(attrs, [:execution_id, :task_id, :status, :result])
      |> validate_required([:execution_id, :task_id, :status])
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
            type: String.t(),
            data: map() | nil,
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "orchestrator_events" do
      field(:type, :string)
      field(:data, :map)
      timestamps()
    end

    def event_changeset(event, attrs) do
      event
      |> cast(attrs, [:type, :data])
      |> validate_required([:type])
    end
  end

  defmodule PerformanceMetric do
    @moduledoc """
    Schema for performance metrics.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{
            id: binary(),
            execution_id: binary(),
            metric_name: String.t(),
            value: float(),
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "orchestrator_performance_metrics" do
      field(:execution_id, :binary_id)
      field(:metric_name, :string)
      field(:value, :float)
      timestamps()
    end

    def performance_metric_changeset(metric, attrs) do
      metric
      |> cast(attrs, [:execution_id, :metric_name, :value])
      |> validate_required([:execution_id, :metric_name, :value])
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
            pattern_type: String.t(),
            pattern_data: map(),
            confidence: float(),
            inserted_at: DateTime.t(),
            updated_at: DateTime.t()
          }

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "orchestrator_learning_patterns" do
      field(:pattern_type, :string)
      field(:pattern_data, :map)
      field(:confidence, :float)
      timestamps()
    end

    def learning_pattern_changeset(pattern, attrs) do
      pattern
      |> cast(attrs, [:pattern_type, :pattern_data, :confidence])
      |> validate_required([:pattern_type, :pattern_data])
    end
  end
end
