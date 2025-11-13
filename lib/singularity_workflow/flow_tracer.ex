defmodule Singularity.Workflow.FlowTracer do
  @moduledoc """
  Flow tracing via telemetry - tracks execution paths through workflows.

  Emits telemetry events that capture the flow of execution through a workflow,
  enabling visualization and debugging of workflow execution paths.

  ## Flow Tracing Events

  - `[:singularity_workflow, :flow, :step_transition]` - Step state transition
  - `[:singularity_workflow, :flow, :dependency_satisfied]` - Dependency satisfied, step ready
  - `[:singularity_workflow, :flow, :parallel_branch]` - Parallel execution branch detected
  - `[:singularity_workflow, :flow, :merge_point]` - Multiple dependencies merge

  ## Usage

      # In your application, attach handlers to visualize flows
      :telemetry.attach(
        "flow-visualizer",
        [:singularity_workflow, :flow, :step_transition],
        &MyApp.FlowVisualizer.handle_transition/4,
        %{}
      )
  """

  @doc """
  Emit a step transition event (created → started → completed/failed).
  """
  @spec trace_step_transition(
          run_id :: binary(),
          step_slug :: String.t(),
          from_status :: String.t(),
          to_status :: String.t(),
          metadata :: map()
        ) :: :ok
  def trace_step_transition(run_id, step_slug, from_status, to_status, metadata \\ %{}) do
    :telemetry.execute(
      [:singularity_workflow, :flow, :step_transition],
      %{timestamp: System.system_time()},
      Map.merge(
        %{
          run_id: run_id,
          step_slug: step_slug,
          from_status: from_status,
          to_status: to_status
        },
        metadata
      )
    )
  end

  @doc """
  Emit a dependency satisfaction event (step becomes ready to execute).
  """
  @spec trace_dependency_satisfied(
          run_id :: binary(),
          step_slug :: String.t(),
          parent_step :: String.t(),
          remaining_deps :: integer()
        ) :: :ok
  def trace_dependency_satisfied(run_id, step_slug, parent_step, remaining_deps) do
    :telemetry.execute(
      [:singularity_workflow, :flow, :dependency_satisfied],
      %{timestamp: System.system_time()},
      %{
        run_id: run_id,
        step_slug: step_slug,
        parent_step: parent_step,
        remaining_deps: remaining_deps
      }
    )
  end

  @doc """
  Emit a parallel branch event (multiple steps executing concurrently).
  """
  @spec trace_parallel_branch(
          run_id :: binary(),
          branch_steps :: [String.t()],
          parent_step :: String.t()
        ) :: :ok
  def trace_parallel_branch(run_id, branch_steps, parent_step) do
    :telemetry.execute(
      [:singularity_workflow, :flow, :parallel_branch],
      %{timestamp: System.system_time(), branch_count: length(branch_steps)},
      %{
        run_id: run_id,
        branch_steps: branch_steps,
        parent_step: parent_step
      }
    )
  end

  @doc """
  Emit a merge point event (multiple dependencies converge on one step).
  """
  @spec trace_merge_point(
          run_id :: binary(),
          step_slug :: String.t(),
          dependencies :: [String.t()]
        ) :: :ok
  def trace_merge_point(run_id, step_slug, dependencies) do
    :telemetry.execute(
      [:singularity_workflow, :flow, :merge_point],
      %{timestamp: System.system_time(), dependency_count: length(dependencies)},
      %{
        run_id: run_id,
        step_slug: step_slug,
        dependencies: dependencies
      }
    )
  end

  @doc """
  Emit workflow structure (DAG topology) when workflow is initialized.
  """
  @spec trace_workflow_structure(
          run_id :: binary(),
          workflow_slug :: String.t(),
          steps :: [map()],
          dependencies :: [{String.t(), String.t()}]
        ) :: :ok
  def trace_workflow_structure(run_id, workflow_slug, steps, dependencies) do
    # Build adjacency list for visualization
    adjacency_list =
      dependencies
      |> Enum.group_by(fn {_step, depends_on} -> depends_on end, fn {step, _} -> step end)
      |> Enum.map(fn {parent, children} -> {parent, children} end)
      |> Map.new()

    :telemetry.execute(
      [:singularity_workflow, :flow, :structure],
      %{timestamp: System.system_time()},
      %{
        run_id: run_id,
        workflow_slug: workflow_slug,
        step_count: length(steps),
        dependency_count: length(dependencies),
        steps: Enum.map(steps, &Map.take(&1, [:step_slug, :depends_on])),
        adjacency_list: adjacency_list
      }
    )
  end
end
