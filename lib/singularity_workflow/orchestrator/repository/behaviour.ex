defmodule Singularity.Workflow.Orchestrator.Repository.Behaviour do
  @moduledoc """
  Behaviour definition for the orchestrator repository module so it can be mocked in tests.
  """

  alias Singularity.Workflow.Orchestrator.Schemas

  @callback create_execution(map(), term()) ::
              {:ok, Schemas.Execution.t()} | {:error, any()}
  @callback update_execution_status(
              Schemas.Execution.t(),
              String.t(),
              term(),
              keyword()
            ) :: {:ok, Schemas.Execution.t()} | {:error, any()}
  @callback create_task_execution(map(), term()) ::
              {:ok, Schemas.TaskExecution.t()} | {:error, any()}
  @callback update_task_execution_status(
              Schemas.TaskExecution.t(),
              String.t(),
              term(),
              keyword()
            ) :: {:ok, Schemas.TaskExecution.t()} | {:error, any()}
  @callback get_execution(String.t(), term()) ::
              {:ok, Schemas.Execution.t()} | {:error, any()}
end
