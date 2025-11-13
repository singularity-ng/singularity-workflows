defmodule Singularity.Workflow.WorkflowSupervisor do
  @moduledoc """
  Supervisor wrapper that keeps backwards compatibility with the original
  `Singularity.Workflow.WorkflowSupervisor` API used throughout the umbrella.

  Internally it starts the newer `Singularity.Workflow.Workflow` process that orchestrates
  executions.  Multiple supervisors can run concurrently – the shared registry
  used by `Singularity.Workflow.Workflow` is started on demand.
  """

  use Supervisor

  @type option ::
          {:workflow, module()}
          | {:repo, module()}
          | {:workflow_name, String.t()}
          | {:name, atom()}
          | {:enabled, boolean()}

  @doc """
  Child specification so the supervisor can be started directly inside a
  supervision tree (e.g. `CentralCloud.Application`).
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      shutdown: 5000
    }
  end

  @doc """
  Start the workflow supervisor.  If the `:enabled` option is set to `false`
  we return `:ignore`, mirroring how the legacy code toggled feature flags.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    if Keyword.get(opts, :enabled, true) do
      ensure_registry_started()
      Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
    else
      :ignore
    end
  end

  @impl Supervisor
  @spec init(keyword()) :: {:ok, tuple()}
  def init(opts) do
    workflow_module = Keyword.fetch!(opts, :workflow)
    repo = resolve_repo(opts, workflow_module)
    workflow_name = Keyword.get(opts, :workflow_name, default_workflow_name(workflow_module))

    children = [
      %{
        id: {Singularity.Workflow.Runtime.Workflow, workflow_module},
        start:
          {Singularity.Workflow.Runtime.Workflow, :start_link,
           [workflow_name, workflow_module, [repo: repo]]},
        restart: :permanent,
        shutdown: 15_000,
        type: :worker
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Start a workflow process outside of a supervision tree (useful for tests or
  ad-hoc execution scenarios).
  """
  @spec start_workflow(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_workflow(workflow_module, opts \\ []) do
    ensure_registry_started()
    workflow_name = Keyword.get(opts, :workflow_name, default_workflow_name(workflow_module))
    repo = resolve_repo(opts, workflow_module)
    Singularity.Workflow.Runtime.Workflow.start_link(workflow_name, workflow_module, repo: repo)
  end

  @doc """
  List workflow processes currently registered with the global workflow
  registry.
  """
  @spec list_workflows() :: [String.t()]
  def list_workflows do
    case Process.whereis(Singularity.Workflow.WorkflowRegistry) do
      nil ->
        []

      _pid ->
        Registry.select(Singularity.Workflow.WorkflowRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp ensure_registry_started do
    case Process.whereis(Singularity.Workflow.WorkflowRegistry) do
      nil ->
        case Registry.start_link(keys: :unique, name: Singularity.Workflow.WorkflowRegistry) do
          {:ok, _pid} ->
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            raise "Failed to start Singularity.Workflow.WorkflowRegistry: #{inspect(reason)}"
        end

      _pid ->
        :ok
    end
  end

  @spec default_workflow_name(module()) :: String.t()
  defp default_workflow_name(workflow_module) do
    workflow_module
    |> Module.split()
    |> Enum.map_join(".", &Macro.underscore/1)
  end

  @spec resolve_repo(keyword(), module()) :: module() | no_return()
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
        raise "Singularity.Workflow.WorkflowSupervisor could not determine an Ecto repo. Pass :repo option explicitly."
    end
  end

  defp repo_from_app(nil), do: nil

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
end
