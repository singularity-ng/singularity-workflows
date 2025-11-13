defmodule Singularity.Workflow.Repo.Migrations.CreateHtdagTables do
  use Ecto.Migration

  def change do
    # Orchestrator Task Graphs table
    create table(:orchestrator_task_graphs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :goal, :text, null: false
      add :decomposer_module, :string, null: false
      add :task_graph, :map, null: false
      add :metadata, :map, null: false, default: fragment("'{}'::jsonb")
      add :max_depth, :integer, default: 5
      add :status, :string, null: false, default: "pending"
      timestamps(type: :utc_datetime)
    end

    create index(:orchestrator_task_graphs, [:name])
    create index(:orchestrator_task_graphs, [:inserted_at])

    # Orchestrator Workflows table
    create table(:orchestrator_workflows, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :description, :text
      add :task_graph_id,
          references(:orchestrator_task_graphs, type: :uuid, on_delete: :delete_all),
          null: false
      add :workflow_definition, :map, null: false
      add :step_functions, :map, null: false
      add :config, :map, null: false, default: fragment("'{}'::jsonb")
      add :metadata, :map, null: false, default: fragment("'{}'::jsonb")
      add :max_parallel, :integer, default: 10
      add :retry_attempts, :integer, default: 3
      add :status, :string, default: "created"
      timestamps(type: :utc_datetime)
    end

    create index(:orchestrator_workflows, [:name])
    create index(:orchestrator_workflows, [:task_graph_id])
    create index(:orchestrator_workflows, [:status])
    create index(:orchestrator_workflows, [:inserted_at])

    # Orchestrator Executions table
    create table(:orchestrator_executions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :workflow_id, references(:orchestrator_workflows, type: :uuid, on_delete: :delete_all), null: false
      add :execution_id, :string, null: false
      add :goal_context, :map, null: false
      add :status, :string, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :duration_ms, :integer
      add :result, :map
      add :error_message, :text
      timestamps(type: :utc_datetime)
    end

    create index(:orchestrator_executions, [:workflow_id])
    create index(:orchestrator_executions, [:execution_id])
    create index(:orchestrator_executions, [:status])
    create index(:orchestrator_executions, [:started_at])

    # Orchestrator Task Executions table
    create table(:orchestrator_task_executions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :execution_id, references(:orchestrator_executions, type: :uuid, on_delete: :delete_all), null: false
      add :task_id, :string, null: false
      add :task_name, :string, null: false
      add :status, :string, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :duration_ms, :integer
      add :result, :map
      add :error_message, :text
      add :retry_count, :integer, default: 0
      timestamps(type: :utc_datetime)
    end

    create index(:orchestrator_task_executions, [:execution_id])
    create index(:orchestrator_task_executions, [:task_id])
    create index(:orchestrator_task_executions, [:status])
    create index(:orchestrator_task_executions, [:started_at])

    # Orchestrator Events table
    create table(:orchestrator_events, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :execution_id, references(:orchestrator_executions, type: :uuid, on_delete: :delete_all)
      add :task_execution_id, references(:orchestrator_task_executions, type: :uuid, on_delete: :delete_all)
      add :event_type, :string, null: false
      add :event_data, :map, null: false
      add :occurred_at, :utc_datetime, null: false, default: fragment("NOW()")
      timestamps(type: :utc_datetime)
    end

    create index(:orchestrator_events, [:execution_id])
    create index(:orchestrator_events, [:task_execution_id])
    create index(:orchestrator_events, [:event_type])
    create index(:orchestrator_events, [:occurred_at])

    # Orchestrator Performance Metrics table
    create table(:orchestrator_performance_metrics, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :workflow_id, references(:orchestrator_workflows, type: :uuid, on_delete: :delete_all), null: false
      add :task_id, :string
      add :metric_type, :string, null: false
      add :metric_value, :float, null: false
      add :metric_unit, :string
      add :context, :map, null: false, default: fragment("'{}'::jsonb")
      add :recorded_at, :utc_datetime, null: false, default: fragment("NOW()")
      timestamps(type: :utc_datetime)
    end

    create index(:orchestrator_performance_metrics, [:workflow_id])
    create index(:orchestrator_performance_metrics, [:task_id])
    create index(:orchestrator_performance_metrics, [:metric_type])
    create index(:orchestrator_performance_metrics, [:recorded_at])

    # Orchestrator Learning Patterns table
    create table(:orchestrator_learning_patterns, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :workflow_name, :string, null: false
      add :pattern_type, :string, null: false
      add :pattern_data, :map, null: false
      add :confidence_score, :float, default: 0.0
      add :usage_count, :integer, default: 0
      add :last_used_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:orchestrator_learning_patterns, [:workflow_name])
    create index(:orchestrator_learning_patterns, [:pattern_type])
    create index(:orchestrator_learning_patterns, [:confidence_score])
    create index(:orchestrator_learning_patterns, [:last_used_at])
  end
end
