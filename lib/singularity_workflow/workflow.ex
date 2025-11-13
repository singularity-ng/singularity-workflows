defmodule Singularity.Workflow.Workflow do
  @moduledoc """
  Public API for orchestrating Singularity.Workflow workflows.

  Provides functions to start, execute, monitor, and gather metrics for
  database-backed workflows executed by the Singularity.Workflow runtime. Repositories
  are resolved automatically from the workflow module's owning OTP
  application, but can also be supplied explicitly via the `:repo` option.
  """

  require Logger
  import Ecto.Query

  alias Singularity.Workflow.DAG.RunInitializer
  alias Singularity.Workflow.DAG.TaskExecutor
  alias Singularity.Workflow.DAG.WorkflowDefinition
  alias Singularity.Workflow.Runtime.Workflow, as: RuntimeWorkflow
  alias Singularity.Workflow.StepState
  alias Singularity.Workflow.WorkflowRun

  @type run_id :: Ecto.UUID.t()
  @default_poll_interval 200
  @default_timeout 30_000

  defmodule Behaviour do
    @moduledoc false

    @type run_id :: Ecto.UUID.t()

    @callback start_link(String.t(), module(), keyword()) :: {:ok, pid()} | {:error, term()}
    @callback enqueue(pid(), atom(), map()) :: :ok | {:error, term()}
    @callback update(pid(), atom(), map()) :: :ok | {:error, term()}
    @callback get_parent(pid()) :: pid() | nil
    @callback execute(module(), map(), keyword()) ::
                {:ok, run_id()} | {:error, term()}
    @callback await(run_id(), keyword()) :: {:ok, map()} | {:error, term()}
    @callback status(run_id(), keyword()) :: {:ok, map()} | {:error, term()}
    @callback metrics(run_id(), keyword()) :: {:ok, map()} | {:error, term()}
  end

  @doc false
  @spec start_link(String.t(), module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(workflow_name, workflow_module, opts \\ []) do
    RuntimeWorkflow.start_link(workflow_name, workflow_module, opts)
  end

  @doc false
  defdelegate enqueue(workflow_pid, step, input), to: RuntimeWorkflow

  @doc false
  defdelegate update(workflow_pid, action, job_data), to: RuntimeWorkflow

  @doc false
  defdelegate get_parent(workflow_pid), to: RuntimeWorkflow

  @doc """
  Provides the workflow macro for defining Singularity.Workflow workflows.
  """
  defmacro __using__(opts \\ []) do
    quote do
      use Singularity.Workflow.Runtime.Workflow, unquote(opts)
    end
  end

  @doc """
  Start executing a workflow asynchronously.

  Returns `{:ok, run_id}` on success.  The caller may subsequently use
  `status/2`, `await/3`, or `metrics/2` to observe progress.
  """
  @spec execute(module(), map(), keyword()) :: {:ok, run_id()} | {:error, term()}
  def execute(workflow_module, input, opts \\ []) when is_map(input) do
    repo = resolve_repo(opts, workflow_module)

    with {:ok, definition} <- WorkflowDefinition.parse(workflow_module),
         {:ok, run_id} <- RunInitializer.initialize(definition, input, repo) do
      start_async_runner(run_id, definition, repo, opts)
      {:ok, run_id}
    else
      {:error, reason} ->
        Logger.error("Singularity.Workflow.Workflow failed to start run",
          workflow: workflow_module,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Await completion of a workflow run.

  Options:
    * `:timeout` – total time in milliseconds to wait (default 30_000)
    * `:poll_interval` – polling interval in milliseconds (default 200)
    * `:repo` – explicit repo module

  Returns:
    * `{:ok, output}` on success
    * `{:error, :timeout}` when the timeout elapses
    * `{:error, reason}` on failure
  """
  @spec await(run_id(), keyword()) :: {:ok, map()} | {:error, term()}
  def await(run_id, opts \\ []) do
    repo = resolve_repo(opts)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_await(run_id, repo, poll_interval, deadline)
  end

  @spec do_await(run_id(), module(), integer(), integer()) :: {:ok, map()} | {:error, term()}
  defp do_await(run_id, repo, poll_interval, deadline) do
    case repo.get(WorkflowRun, run_id) do
      nil ->
        {:error, :not_found}

      %WorkflowRun{status: "completed", output: output} ->
        {:ok, output || %{}}

      %WorkflowRun{status: "failed", error_message: error} ->
        {:error, {:run_failed, error}}

      _ ->
        if System.monotonic_time(:millisecond) > deadline do
          {:error, :timeout}
        else
          Process.sleep(poll_interval)
          do_await(run_id, repo, poll_interval, deadline)
        end
    end
  end

  @doc """
  Retrieve the current status of a workflow run.

  The response contains the overall run state and a list of steps with their
  individual statuses.
  """
  @spec status(run_id(), keyword()) :: {:ok, map()} | {:error, term()}
  def status(run_id, opts \\ []) do
    repo = resolve_repo(opts)

    case repo.get(WorkflowRun, run_id) do
      %WorkflowRun{} = run ->
        steps =
          StepState
          |> where(run_id: ^run_id)
          |> repo.all()
          |> Enum.map(&format_step/1)

        {:ok,
         %{
           id: run_id,
           workflow: run.workflow_slug,
           state: status_atom(run.status),
           started_at: run.started_at,
           completed_at: run.completed_at,
           failed_at: run.failed_at,
           error: run.error_message,
           steps: steps
         }}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Compute simple execution metrics for a workflow run.

  Metrics include:
    * `:execution_time_ms`
    * `:success_rate`
    * `:error_rate`
    * `:throughput` (completed steps per second)
  """
  @spec metrics(run_id(), keyword()) :: {:ok, map()} | {:error, term()}
  def metrics(run_id, opts \\ []) do
    repo = resolve_repo(opts)

    case repo.get(WorkflowRun, run_id) do
      %WorkflowRun{} = run ->
        steps =
          StepState
          |> where(run_id: ^run_id)
          |> repo.all()

        completed = Enum.count(steps, &(&1.status == "completed"))
        failed = Enum.count(steps, &(&1.status == "failed"))
        total = max(Enum.count(steps), 1)

        duration_ms =
          case {run.started_at, run.completed_at} do
            {%DateTime{} = start, %DateTime{} = finish} ->
              DateTime.diff(finish, start, :millisecond)

            _ ->
              nil
          end

        throughput =
          if duration_ms == nil or duration_ms == 0 do
            completed
          else
            completed * 1000 / duration_ms
          end

        {:ok,
         %{
           execution_time_ms: duration_ms,
           success_rate: completed / total,
           error_rate: failed / total,
           throughput: throughput
         }}

      nil ->
        {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec start_async_runner(run_id(), WorkflowDefinition.t(), module(), keyword()) :: :ok
  defp start_async_runner(run_id, definition, repo, opts) do
    task_opts = Keyword.take(opts, [:timeout, :poll_interval, :worker_id, :batch_size])

    ensure_task_supervisor_started()

    Task.Supervisor.start_child(Singularity.Workflow.TaskSupervisor, fn ->
      TaskExecutor.execute_run(run_id, definition, repo, task_opts)
    end)
  end

  @spec ensure_task_supervisor_started() :: :ok
  defp ensure_task_supervisor_started do
    case Process.whereis(Singularity.Workflow.TaskSupervisor) do
      nil ->
        {:ok, _pid} =
          Task.Supervisor.start_link(
            name: Singularity.Workflow.TaskSupervisor,
            strategy: :one_for_one
          )

        :ok

      _pid ->
        :ok
    end
  end

  @spec resolve_repo(keyword()) :: module() | no_return()
  defp resolve_repo(opts), do: resolve_repo(opts, nil)

  @spec resolve_repo(keyword(), module() | nil) :: module() | no_return()
  defp resolve_repo(opts, workflow_module) do
    cond do
      repo = Keyword.get(opts, :repo) ->
        repo

      repo = repo_from_app(workflow_module) ->
        repo

      Code.ensure_loaded?(CentralCloud.Repo) ->
        CentralCloud.Repo

      Code.ensure_loaded?(Singularity.Repo) ->
        Singularity.Repo

      Code.ensure_loaded?(Nexus.Repo) ->
        Nexus.Repo

      true ->
        raise "Singularity.Workflow.Workflow could not determine an Ecto repo. Pass :repo option explicitly."
    end
  end

  @spec repo_from_app(nil) :: nil
  defp repo_from_app(nil), do: nil

  @spec repo_from_app(module()) :: module() | nil
  defp repo_from_app(workflow_module) do
    case Application.get_application(workflow_module) do
      nil ->
        nil

      app ->
        app
        |> Application.get_env(:ecto_repos, [])
        |> List.first()
    end
  end

  @spec format_step(StepState.t()) :: map()
  defp format_step(%StepState{} = step) do
    %{
      name: step.step_slug,
      status: status_atom(step.status),
      started_at: step.started_at,
      completed_at: step.completed_at,
      failed_at: step.failed_at,
      attempts: step.attempts_count,
      error: step.error_message
    }
  end

  @spec status_atom(String.t()) :: :completed | :started | :failed | :created
  defp status_atom("completed"), do: :completed
  defp status_atom("started"), do: :started
  defp status_atom("failed"), do: :failed
  defp status_atom(_), do: :created
end
