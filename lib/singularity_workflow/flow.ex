defmodule Singularity.Workflow.Flow do
  @moduledoc """
  DSL for defining workflows as flows with visualization support.

  Provides a clean, declarative syntax for defining workflows that can be
  automatically visualized and traced.

  ## Usage

      defmodule MyWorkflow do
        use Singularity.Workflow.Flow

        flow "Process Order" do
          step :fetch_order, &__MODULE__.fetch_order/1
          step :validate, &__MODULE__.validate/1, depends_on: [:fetch_order]
          step :charge, &__MODULE__.charge/1, depends_on: [:validate]
          step :ship, &__MODULE__.ship/1, depends_on: [:charge]
        end

        def fetch_order(input), do: {:ok, input}
        def validate(input), do: {:ok, input}
        def charge(input), do: {:ok, input}
        def ship(input), do: {:ok, input}
      end

  ## Parallel Execution

      flow "Data Pipeline" do
        step :fetch, &__MODULE__.fetch/1
        step :analyze, &__MODULE__.analyze/1, depends_on: [:fetch]
        step :summarize, &__MODULE__.summarize/1, depends_on: [:fetch]
        step :save, &__MODULE__.save/1, depends_on: [:analyze, :summarize]
      end

  Steps `analyze` and `summarize` run in parallel!

  ## Map Steps

      flow "Batch Process" do
        step :fetch_items, &__MODULE__.fetch_items/1
        step :process_item, &__MODULE__.process_item/1,
          depends_on: [:fetch_items],
          map: true  # Creates N tasks, one per item
        step :aggregate, &__MODULE__.aggregate/1, depends_on: [:process_item]
      end

  ## Flow Structure & Visualization

  The DSL provides access to flow metadata for custom visualization:

      # Get flow structure (JSON-serializable)
      {:ok, structure} = Singularity.Workflow.Flow.get_structure(MyWorkflow)
      # Returns: %{name: "...", steps: [...], dependencies: [...], step_count: N}

      # Generate Mermaid diagram (for documentation/debugging)
      diagram = Singularity.Workflow.Flow.to_mermaid(MyWorkflow)
      # Returns Mermaid graph syntax (compatible with GitHub, GitLab, etc.)

  ## Telemetry Integration

  All flows automatically emit telemetry events for tracing:
  - `[:singularity_workflow, :flow, :structure]` - Workflow structure
  - `[:singularity_workflow, :flow, :step_transition]` - Step transitions
  - `[:singularity_workflow, :flow, :parallel_branch]` - Parallel branches
  """

  defmacro __using__(_opts) do
    quote do
      import Singularity.Workflow.Flow
    end
  end

  @doc """
  Define a workflow flow with steps.
  """
  defmacro flow(name, do: block) do
    quote do
      @workflow_name unquote(name)
      @workflow_steps []

      unquote(block)

      def __workflow_steps__ do
        @workflow_steps
        |> Enum.reverse()
        |> Enum.map(fn {step_slug, step_fn, opts} ->
          {step_slug, step_fn, opts}
        end)
      end

      def __workflow_name__ do
        @workflow_name
      end
    end
  end

  @doc """
  Define a step in the flow.
  """
  defmacro step(step_slug, step_fn, opts \\ []) do
    quote do
      @workflow_steps [
        {unquote(step_slug), unquote(step_fn), unquote(opts)}
        | @workflow_steps
      ]
    end
  end

  @doc """
  Get the flow structure for visualization.
  """
  @spec get_structure(module()) :: {:ok, map()} | {:error, term()}
  def get_structure(workflow_module) do
    try do
      steps = workflow_module.__workflow_steps__()
      name = workflow_module.__workflow_name__()

      # Extract step information
      step_info =
        Enum.map(steps, fn {step_slug, _step_fn, opts} ->
          %{
            step_slug: step_slug,
            depends_on: Keyword.get(opts, :depends_on, []),
            map: Keyword.get(opts, :map, false)
          }
        end)

      # Build dependency graph
      dependencies =
        Enum.flat_map(step_info, fn step ->
          Enum.map(step.depends_on, fn dep ->
            {step.step_slug, dep}
          end)
        end)

      structure = %{
        name: name,
        workflow_module: workflow_module,
        steps: step_info,
        dependencies: dependencies,
        step_count: length(step_info)
      }

      {:ok, structure}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  @doc """
  Convert workflow to Mermaid diagram format.

  Useful for documentation, debugging, and sharing workflow structures.
  Mermaid diagrams render in GitHub, GitLab, and many documentation tools.

  ## Example

      diagram = Singularity.Workflow.Flow.to_mermaid(MyWorkflow)
      # Paste into GitHub/GitLab markdown or Mermaid Live Editor

  ## Returns

  Mermaid graph syntax as a string, or error message on failure.
  """
  @spec to_mermaid(module()) :: String.t()
  def to_mermaid(workflow_module) do
    case get_structure(workflow_module) do
      {:ok, structure} ->
        build_mermaid_diagram(structure)

      {:error, reason} ->
        "%% Error generating Mermaid diagram: #{reason}"
    end
  end

  @spec build_mermaid_diagram(map()) :: String.t()
  defp build_mermaid_diagram(structure) do
    lines = [
      "graph TB",
      "    %% Workflow: #{structure.name}",
      "    %% Generated by Singularity.Workflow.Flow"
    ]

    # Add nodes
    node_lines =
      Enum.map(structure.steps, fn step ->
        node_id = sanitize_node_id(step.step_slug)
        label = format_step_label(step)
        "    #{node_id}[#{label}]"
      end)

    # Add edges (dependencies)
    edge_lines =
      Enum.flat_map(structure.steps, fn step ->
        Enum.map(step.depends_on, fn dep ->
          dep_id = sanitize_node_id(dep)
          step_id = sanitize_node_id(step.step_slug)
          "    #{dep_id} --> #{step_id}"
        end)
      end)

    (lines ++ node_lines ++ edge_lines)
    |> Enum.join("\n")
  end

  @spec sanitize_node_id(atom() | String.t()) :: String.t()
  defp sanitize_node_id(atom_or_string) do
    atom_or_string
    |> to_string()
    |> String.replace(":", "_")
    |> String.replace(".", "_")
    |> String.replace("-", "_")
  end

  @spec format_step_label(map()) :: String.t()
  defp format_step_label(step) do
    base_label = step.step_slug |> to_string()
    if step.map, do: "#{base_label}<br/>(MAP)", else: base_label
  end
end
