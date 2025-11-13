defmodule Singularity.Workflow.Execution.Strategy do
  @moduledoc """
  Execution strategy for workflow steps.

  Provides different execution modes:
  - `:local` - Execute locally in the current process
  - `:distributed` - Execute across multiple nodes using PostgreSQL + pgmq

  ## Usage

      # Local execution (default)
      Strategy.execute(step_fn, input, %{execution: :local})

      # Distributed execution across nodes
      Strategy.execute(step_fn, input, %{
        execution: :distributed,
        resources: [gpu: true],
        queue: :gpu_workers
      })

  ## Implementation Note

  The distributed backend uses PostgreSQL + pgmq for job coordination.
  Oban is used internally as an implementation detail and is not exposed
  to library users.
  """

  require Logger
  alias Singularity.Workflow.Execution.{DirectBackend, DistributedBackend}

  @type execution_config :: %{
          execution: :local | :distributed,
          resources: keyword(),
          queue: atom() | nil,
          timeout: integer() | nil
        }

  @doc """
  Execute a step function using the specified execution strategy.
  """
  @spec execute(function(), map(), ExecutionConfig.t(), map()) :: {:ok, map()} | {:error, term()}
  def execute(step_fn, input, config, context \\ %{}) do
    case config.execution do
      :local -> DirectBackend.execute(step_fn, input, config, context)
      :distributed -> DistributedBackend.execute(step_fn, input, config, context)
      other -> {:error, {:unsupported_execution_mode, other}}
    end
  end

  @doc """
  Check if an execution mode is available.
  """
  @spec available?(:local | :distributed) :: boolean()
  def available?(:local), do: true
  def available?(:distributed), do: DistributedBackend.available?()
end
