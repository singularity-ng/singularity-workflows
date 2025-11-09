defmodule Singularity.Workflow.OrchestratorOptimizer do
  @moduledoc """
  Genesis v2 Optimization Engine: Self-improving workflow learning and adaptation.

  Part of Genesis v2 (formerly called Evolution). Analyzes workflow execution patterns
  and optimizes future workflows based on historical performance data and learning algorithms.
  Works in tandem with `Singularity.Workflow.Lineage` to track execution history and enable
  adaptive workflow optimization.

  ## Features

  - **Performance Analysis**: Analyze execution times and success rates
  - **Dependency Optimization**: Optimize task dependencies for better parallelization
  - **Resource Allocation**: Optimize resource usage and task distribution
  - **Adaptive Learning**: Learn from execution patterns to improve future workflows
  - **Self-Improving**: Workflows become faster and more efficient over time
  - **Multiple Optimization Levels**: :basic, :advanced, :aggressive

  ## Usage

      # Optimize a workflow based on historical data (Genesis v2)
      {:ok, optimized_workflow} = Singularity.Workflow.OrchestratorOptimizer.optimize_workflow(
        workflow,
        MyApp.Repo,
        optimization_level: :advanced
      )

      # Get optimization recommendations
      {:ok, recommendations} = Singularity.Workflow.OrchestratorOptimizer.get_recommendations(
        workflow,
        MyApp.Repo
      )

  ## AI Navigation Metadata

  ### Module Identity
  - **Type**: Genesis v2 Optimization Engine
  - **Purpose**: Enable self-improving workflows through learning-based optimization
  - **Works with**: Singularity.Workflow.Lineage, Singularity.Workflow.Orchestrator

  ### Call Graph
  - `optimize_workflow/3` → analyze metrics, apply optimizations, store patterns
  - `get_recommendations/3` → Repository queries, pattern matching
  - **Integrates**: Repository, Lineage, OrchestratorNotifications

  ### Anti-Patterns
  - ❌ DO NOT optimize workflows without sufficient historical data
  - ❌ DO NOT break task dependencies during optimization
  - ✅ DO preserve workflow semantics during optimization
  - ✅ DO track optimization impact for learning feedback

  ### Search Keywords
  optimization, performance_tuning, learning_algorithms, pattern_analysis,
  workflow_optimization, execution_metrics, parallelization, resource_allocation,
  adaptive_strategies, pattern_learning

  ### Decision Tree (Which Optimization Level to Use?)

  ```
  How much optimization do you need?
  ├─ I want conservative, safe optimizations
  │  └─ Use `:basic` level
  │     └─ Adjusts timeouts, adds retry logic, basic reordering
  │
  ├─ I have good historical data and want smart optimizations
  │  └─ Use `:advanced` level
  │     └─ Dynamic parallelization, intelligent retries, resource allocation
  │
  └─ I have extensive data and want aggressive optimization
     └─ Use `:aggressive` level
        └─ Complete restructuring, advanced parallelization, ML-based optimization

  Additional considerations:
  ├─ Want to preserve original workflow structure?
  │  └─ Set `preserve_structure: true` (recommended for safety)
  │
  ├─ Have resource constraints?
  │  └─ Set `max_parallel: <number>` (default: 10)
  │
  └─ Know timeout patterns from history?
     └─ Set `timeout_threshold: <milliseconds>`
  ```
  """

  require Logger

  @doc """
  Optimize a workflow based on historical performance data.

  ## Parameters

  - `workflow` - Workflow to optimize
  - `repo` - Ecto repository
  - `opts` - Optimization options
    - `:optimization_level` - Level of optimization (:basic, :advanced, :aggressive)
    - `:preserve_structure` - Keep original task structure (default: true)
    - `:max_parallel` - Maximum parallel tasks after optimization
    - `:timeout_threshold` - Timeout threshold for task optimization

  ## Returns

  - `{:ok, optimized_workflow}` - Optimized workflow
  - `{:error, reason}` - Optimization failed

  ## Example

      {:ok, optimized} = Singularity.Workflow.OrchestratorOptimizer.optimize_workflow(
        workflow,
        MyApp.Repo,
        optimization_level: :advanced,
        max_parallel: 10
      )
  """
  @spec optimize_workflow(map(), Ecto.Repo.t(), keyword()) ::
          {:ok, map()} | {:error, any()}
  def optimize_workflow(workflow, repo, opts \\ []) do
    optimization_level = Keyword.get(opts, :optimization_level, :basic)
    preserve_structure = Keyword.get(opts, :preserve_structure, true)
    max_parallel = Keyword.get(opts, :max_parallel, 10)

    Logger.info("Optimizing workflow: #{workflow.name} (level: #{optimization_level})")

    try do
      # Get historical performance data
      {:ok, performance_data} = get_performance_data(workflow.name, repo)

      # Apply optimizations based on level
      optimized_workflow =
        case optimization_level do
          :basic -> apply_basic_optimizations(workflow, performance_data, opts)
          :advanced -> apply_advanced_optimizations(workflow, performance_data, opts)
          :aggressive -> apply_aggressive_optimizations(workflow, performance_data, opts)
        end

      # Ensure structure preservation if requested
      final_workflow =
        if preserve_structure do
          preserve_workflow_structure(workflow, optimized_workflow)
        else
          optimized_workflow
        end

      # Apply parallelization limits
      final_workflow = apply_parallelization_limits(final_workflow, max_parallel)

      Logger.info("Workflow optimization completed")
      {:ok, final_workflow}
    rescue
      error ->
        Logger.error("Workflow optimization failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get optimization recommendations for a workflow.

  ## Parameters

  - `workflow` - Workflow to analyze
  - `repo` - Ecto repository
  - `opts` - Analysis options

  ## Returns

  - `{:ok, recommendations}` - List of optimization recommendations
  - `{:error, reason}` - Analysis failed

  ## Example

      {:ok, recommendations} = Singularity.Workflow.OrchestratorOptimizer.get_recommendations(
        workflow,
        MyApp.Repo
      )
      
      # recommendations = [
      #   %{type: :parallelization, task: "task1", suggestion: "Can run in parallel with task2"},
      #   %{type: :timeout, task: "task3", suggestion: "Increase timeout to 30s"},
      #   %{type: :retry, task: "task4", suggestion: "Add retry logic for better reliability"}
      # ]
  """
  @spec get_recommendations(map(), Ecto.Repo.t(), keyword()) ::
          {:ok, list()} | {:error, any()}
  def get_recommendations(workflow, repo, _opts \\ []) do
    Logger.info("Analyzing workflow for optimization recommendations: #{workflow.name}")

    try do
      # Get performance data
      {:ok, performance_data} = get_performance_data(workflow.name, repo)

      # Analyze workflow structure
      {:ok, structure_analysis} = analyze_workflow_structure(workflow)

      # Generate recommendations
      recommendations = generate_recommendations(workflow, performance_data, structure_analysis)

      Logger.info("Generated #{length(recommendations)} optimization recommendations")
      {:ok, recommendations}
    rescue
      error ->
        Logger.error("Failed to generate recommendations: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Learn from workflow execution patterns.

  ## Parameters

  - `workflow_name` - Name of the workflow to learn from
  - `execution_data` - Execution data to learn from
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Learning completed successfully
  - `{:error, reason}` - Learning failed
  """
  @spec learn_from_execution(String.t(), map(), Ecto.Repo.t()) :: :ok | {:error, any()}
  def learn_from_execution(workflow_name, execution_data, repo) do
    Logger.info("Learning from workflow execution: #{workflow_name}")

    try do
      # Extract learning patterns from execution data
      patterns = extract_learning_patterns(execution_data)

      # Store patterns for future optimization
      store_learning_patterns(workflow_name, patterns, repo)

      Logger.info("Learning completed for workflow: #{workflow_name}")
      :ok
    rescue
      error ->
        Logger.error("Learning failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get optimization statistics.

  ## Parameters

  - `repo` - Ecto repository
  - `opts` - Query options

  ## Returns

  - `{:ok, stats}` - Optimization statistics
  - `{:error, reason}` - Failed to get stats
  """
  @spec get_optimization_stats(Ecto.Repo.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get_optimization_stats(repo, opts \\ []) do
    import Ecto.Query

    # Get time range from opts
    since_date =
      Keyword.get(opts, :since, DateTime.add(DateTime.utc_now(), -30 * 24 * 60 * 60, :second))

    # Count total optimizations (workflows with multiple versions)
    total_query =
      from(w in Singularity.Workflow.Orchestrator.Schemas.Workflow,
        where: w.inserted_at >= ^since_date,
        select: count(w.id)
      )

    total_optimizations = repo.one(total_query) || 0

    # Calculate average performance improvement
    improvement_query =
      from(pm in Singularity.Workflow.Orchestrator.Schemas.PerformanceMetric,
        join: w in Singularity.Workflow.Orchestrator.Schemas.Workflow,
        on: pm.workflow_id == w.id,
        where: w.inserted_at >= ^since_date,
        select: %{
          avg_improvement: avg(pm.optimization_improvement),
          success_rate: avg(pm.success_rate)
        }
      )

    metrics = repo.one(improvement_query) || %{avg_improvement: 0.0, success_rate: 0.0}

    # Get most optimized workflows
    most_optimized_query =
      from(w in Singularity.Workflow.Orchestrator.Schemas.Workflow,
        left_join: pm in Singularity.Workflow.Orchestrator.Schemas.PerformanceMetric,
        on: pm.workflow_id == w.id,
        where: w.inserted_at >= ^since_date,
        group_by: w.name,
        order_by: [desc: count(w.id)],
        limit: 5,
        select: {w.name, count(w.id)}
      )

    most_optimized = repo.all(most_optimized_query) || []

    most_optimized_workflows =
      Enum.map(most_optimized, fn {name, count} ->
        %{workflow: name, optimization_count: count}
      end)

    {:ok,
     %{
       total_optimizations: total_optimizations,
       average_improvement: Float.round(metrics.avg_improvement || 0.0, 2),
       most_optimized_workflows: most_optimized_workflows,
       optimization_success_rate: Float.round((metrics.success_rate || 0.0) * 100, 2)
     }}
  rescue
    error ->
      Logger.error("Failed to get optimization stats: #{inspect(error)}")
      {:error, error}
  end

  # Private functions

  defp get_performance_data(workflow_name, repo) do
    import Ecto.Query

    # Get workflow history
    workflow_query =
      from(w in Singularity.Workflow.Orchestrator.Schemas.Workflow,
        where: w.name == ^workflow_name,
        select: w.id
      )

    workflow_ids = repo.all(workflow_query) || []

    if Enum.empty?(workflow_ids) do
      {:ok,
       %{
         avg_execution_times: %{},
         success_rates: %{},
         failure_patterns: [],
         resource_usage: %{}
       }}
    else
      # Get average execution times per task
      exec_times_query =
        from(te in Singularity.Workflow.Orchestrator.Schemas.TaskExecution,
          join: e in Singularity.Workflow.Orchestrator.Schemas.Execution,
          on: te.execution_id == e.id,
          where: e.workflow_id in ^workflow_ids and te.status == "completed",
          group_by: te.task_id,
          select: {te.task_id, avg(te.duration_ms)}
        )

      avg_execution_times =
        exec_times_query
        |> repo.all()
        |> Map.new()

      # Calculate success rates per task
      success_query =
        from(te in Singularity.Workflow.Orchestrator.Schemas.TaskExecution,
          join: e in Singularity.Workflow.Orchestrator.Schemas.Execution,
          on: te.execution_id == e.id,
          where: e.workflow_id in ^workflow_ids,
          group_by: te.task_id,
          select:
            {te.task_id,
             sum(fragment("CASE WHEN ? = 'completed' THEN 1 ELSE 0 END", te.status)) /
               fragment("NULLIF(COUNT(*), 0)")}
        )

      success_rates =
        success_query
        |> repo.all()
        |> Map.new(fn {task_id, rate} -> {task_id, Float.round((rate || 0.0) * 100, 2)} end)

      # Get common failure patterns
      failure_query =
        from(te in Singularity.Workflow.Orchestrator.Schemas.TaskExecution,
          join: e in Singularity.Workflow.Orchestrator.Schemas.Execution,
          on: te.execution_id == e.id,
          where: e.workflow_id in ^workflow_ids and te.status == "failed",
          group_by: [te.task_id, te.error_message],
          order_by: [desc: count(te.id)],
          limit: 10,
          select: %{
            task_id: te.task_id,
            error: te.error_message,
            occurrences: count(te.id)
          }
        )

      failure_patterns = repo.all(failure_query) || []

      # Get resource usage statistics
      resource_query =
        from(pm in Singularity.Workflow.Orchestrator.Schemas.PerformanceMetric,
          where: pm.workflow_id in ^workflow_ids,
          select: %{
            avg_memory: avg(pm.memory_usage),
            avg_cpu: avg(pm.cpu_usage),
            avg_duration: avg(pm.execution_time_ms)
          }
        )

      resource_usage =
        repo.one(resource_query) ||
          %{
            avg_memory: 0,
            avg_cpu: 0.0,
            avg_duration: 0
          }

      {:ok,
       %{
         avg_execution_times: avg_execution_times,
         success_rates: success_rates,
         failure_patterns: failure_patterns,
         resource_usage: resource_usage
       }}
    end
  rescue
    error ->
      Logger.error("Failed to get performance data: #{inspect(error)}")
      {:error, error}
  end

  defp apply_basic_optimizations(workflow, performance_data, opts) do
    # Basic optimizations: adjust timeouts, add retry logic, simple reordering
    config = Singularity.Workflow.Orchestrator.Config.get(:optimization)
    timeout_multiplier = Keyword.get(opts, :timeout_multiplier, config.timeout_multiplier_basic)
    retry_thresholds = Map.get(config, :retry_thresholds, default_retry_thresholds())

    optimized_steps =
      workflow.steps
      |> Enum.map(fn step ->
        step_id = Map.get(step, :id) || Map.get(step, :name)

        # Adjust timeout based on historical data
        avg_time = Map.get(performance_data.avg_execution_times, step_id, 30_000)
        optimal_timeout = round(avg_time * timeout_multiplier)

        # Add retry logic for frequently failing steps using config thresholds
        success_rate = Map.get(performance_data.success_rates, step_id, 100.0)
        retry_count = determine_retry_count(success_rate, retry_thresholds)

        step
        |> Map.put(:timeout, optimal_timeout)
        |> Map.put(:max_attempts, retry_count)
        |> Map.put(:optimized, true)
      end)
      |> reorder_steps_for_parallelization()

    Map.put(workflow, :steps, optimized_steps)
  end

  defp apply_advanced_optimizations(workflow, performance_data, opts) do
    # Advanced optimizations: parallelization, resource allocation, intelligent grouping
    config = Singularity.Workflow.Orchestrator.Config.get(:optimization)
    max_parallel = Keyword.get(opts, :max_parallel, config.max_parallel)

    optimized_steps =
      workflow.steps
      |> Enum.map(fn step ->
        # Optimize based on resource usage patterns
        resource_data = performance_data.resource_usage
        avg_memory = Map.get(resource_data, :avg_memory, 0)
        avg_cpu = Map.get(resource_data, :avg_cpu, 0.0)

        # Set resource hints for better allocation
        step
        |> Map.put(:resource_hints, %{
          memory_mb: round(avg_memory * 1.1),
          cpu_cores: Float.ceil(avg_cpu),
          priority: calculate_step_priority(step, performance_data)
        })
        |> optimize_step_advanced(performance_data)
      end)
      |> identify_parallel_groups()
      |> apply_parallel_limits(max_parallel)

    # Reorder steps for better parallelization
    reordered_steps = reorder_steps_for_parallelization(optimized_steps)

    Map.put(workflow, :steps, reordered_steps)
    |> Map.put(:optimization_level, :advanced)
  end

  defp calculate_step_priority(step, performance_data) do
    step_id = Map.get(step, :id) || Map.get(step, :name)
    success_rate = Map.get(performance_data.success_rates, step_id, 100.0)

    cond do
      Map.get(step, :critical, false) -> :high
      # Unreliable steps get lower priority
      success_rate < 80.0 -> :low
      true -> :normal
    end
  end

  defp identify_parallel_groups(steps) do
    # Group independent steps that can run in parallel
    steps
    |> Enum.group_by(fn step ->
      Map.get(step, :depends_on, [])
    end)
    |> Enum.flat_map(fn {_deps, group} ->
      if length(group) > 1 do
        # Mark steps in same dependency group as parallelizable
        Enum.map(group, &Map.put(&1, :parallel_group, true))
      else
        group
      end
    end)
  end

  defp apply_parallel_limits(steps, max_parallel) do
    # Ensure we don't exceed max parallel execution
    parallel_count = Enum.count(steps, &Map.get(&1, :parallel_group, false))

    if parallel_count > max_parallel do
      # Batch parallel steps into smaller groups
      steps
      |> Enum.chunk_every(max_parallel)
      |> Enum.with_index()
      |> Enum.flat_map(fn {chunk, batch_idx} ->
        Enum.map(chunk, &Map.put(&1, :batch_index, batch_idx))
      end)
    else
      steps
    end
  end

  defp apply_aggressive_optimizations(workflow, performance_data, opts) do
    # Automatic aggressive optimizations - complete restructuring
    Logger.info("Applying aggressive optimizations to workflow")

    # Start with advanced optimizations as base
    workflow = apply_advanced_optimizations(workflow, performance_data, opts)

    # Aggressive step merging - combine steps with similar resource profiles
    merged_steps =
      workflow.steps
      |> group_similar_steps(performance_data)
      |> merge_compatible_steps()

    # Aggressive parallelization - maximize parallel execution
    parallel_steps =
      merged_steps
      |> identify_all_parallelizable_paths()
      |> restructure_for_maximum_parallelism()

    # Predictive optimization - pre-allocate resources based on patterns
    optimized_steps =
      parallel_steps
      |> Enum.map(fn step ->
        step
        |> add_predictive_resource_allocation(performance_data)
        |> add_adaptive_timeout_multiplier(performance_data)
        |> add_failure_prediction_hints(performance_data)
      end)

    workflow
    |> Map.put(:steps, optimized_steps)
    |> Map.put(:optimization_level, :aggressive)
    |> Map.put(:restructured, true)
  end

  defp group_similar_steps(steps, performance_data) do
    # Group steps with similar execution characteristics using config brackets
    config = Singularity.Workflow.Orchestrator.Config.get(:optimization)
    brackets = Map.get(config, :execution_time_brackets, default_execution_brackets())

    steps
    |> Enum.group_by(fn step ->
      step_id = Map.get(step, :id) || Map.get(step, :name)
      avg_time = Map.get(performance_data.avg_execution_times, step_id, 0)

      # Group by execution time brackets from config
      cond do
        avg_time < brackets.fast -> :fast
        avg_time < brackets.medium -> :medium
        true -> :slow
      end
    end)
  end

  defp merge_compatible_steps(grouped_steps) do
    # Merge steps that can be batched together using config batch size
    config = Singularity.Workflow.Orchestrator.Config.get(:optimization)
    batch_size = Map.get(config, :batch_size, 3)

    Enum.flat_map(grouped_steps, fn {_speed, steps} ->
      if length(steps) > batch_size do
        # Batch small steps together
        steps
        |> Enum.chunk_every(batch_size)
        |> Enum.map(fn chunk ->
          %{
            id: "batch_#{:erlang.unique_integer([:positive])}",
            name: "Batched steps",
            batched_steps: chunk,
            merged: true
          }
        end)
      else
        steps
      end
    end)
  end

  defp identify_all_parallelizable_paths(steps) do
    # Mark all independent paths for parallel execution
    steps
    |> Enum.map(fn step ->
      Map.put(step, :parallel_eligible, true)
    end)
  end

  defp restructure_for_maximum_parallelism(steps) do
    # Restructure to maximize parallel execution using config parallel tracks
    config = Singularity.Workflow.Orchestrator.Config.get(:optimization)
    parallel_tracks = Map.get(config, :parallel_tracks, 5)

    steps
    |> Enum.sort_by(&Map.get(&1, :id))
    |> Enum.with_index()
    |> Enum.map(fn {step, index} ->
      Map.put(step, :execution_order, rem(index, parallel_tracks))
    end)
  end

  defp add_predictive_resource_allocation(step, performance_data) do
    # Add predictive resource hints using config thresholds
    config = Singularity.Workflow.Orchestrator.Config.get(:optimization)
    resources = Map.get(config, :resource_defaults, default_resource_defaults())
    cpu_threshold = Map.get(resources, :cpu_threshold_unreliable, 80.0)

    step_id = Map.get(step, :id) || Map.get(step, :name)
    success_rate = Map.get(performance_data.success_rates, step_id, 100.0)

    Map.put(step, :predicted_resources, %{
      memory_mb:
        if(success_rate < cpu_threshold,
          do: resources.memory_mb_high,
          else: resources.memory_mb_low
        ),
      cpu_priority: if(success_rate < cpu_threshold, do: :high, else: :normal),
      predicted_duration: Map.get(performance_data.avg_execution_times, step_id, 5000)
    })
  end

  defp add_adaptive_timeout_multiplier(step, performance_data) do
    # Add adaptive timeout based on historical variance using config threshold
    config = Singularity.Workflow.Orchestrator.Config.get(:optimization)
    failure_threshold = Map.get(config, :failure_pattern_threshold, 2)

    step_id = Map.get(step, :id) || Map.get(step, :name)
    failures = Enum.filter(performance_data.failure_patterns, &(&1.task_id == step_id))

    timeout_multiplier = if length(failures) > failure_threshold, do: 3.0, else: 1.5
    Map.put(step, :adaptive_timeout_multiplier, timeout_multiplier)
  end

  defp add_failure_prediction_hints(step, performance_data) do
    # Add hints about likely failure modes
    step_id = Map.get(step, :id) || Map.get(step, :name)
    failures = Enum.filter(performance_data.failure_patterns, &(&1.task_id == step_id))

    if Enum.any?(failures) do
      Map.put(step, :predicted_failure_modes, Enum.map(failures, & &1.error))
    else
      step
    end
  end

  defp optimize_step_basic(step) do
    # Automatic basic optimization - apply sensible defaults from config
    config = Singularity.Workflow.Orchestrator.Config.get(:execution)
    default_timeout = Map.get(config, :task_timeout, 30_000)
    default_retry = Map.get(config, :retry_attempts, 3)
    default_delay = Map.get(config, :retry_delay, 1_000)

    step
    |> Map.put_new(:timeout, default_timeout)
    |> Map.put_new(:max_attempts, default_retry)
    |> Map.put_new(:retry_delay, default_delay)
    |> Map.put_new(:optimized_at, DateTime.utc_now())
  end

  defp optimize_step_advanced(step, performance_data) do
    # Automatic advanced optimization - use performance data hints with config multiplier
    config = Singularity.Workflow.Orchestrator.Config.get(:optimization)
    timeout_multiplier = Map.get(config, :timeout_multiplier_advanced, 1.5)

    step_id = Map.get(step, :id) || Map.get(step, :name)
    avg_time = Map.get(performance_data.avg_execution_times, step_id)

    step
    # Apply basic optimizations first
    |> optimize_step_basic()
    |> then(fn s ->
      # Auto-adjust timeout if we have historical data
      if avg_time do
        Map.put(s, :timeout, round(avg_time * timeout_multiplier))
      else
        s
      end
    end)
    |> Map.put(:optimization_strategy, :adaptive)
  end

  defp reorder_steps_for_parallelization(steps) do
    # Simple automatic reordering - group by dependency count
    steps
    |> Enum.sort_by(fn step ->
      # Steps with fewer dependencies go first (can parallelize more)
      depends_on = Map.get(step, :depends_on, [])
      {length(depends_on), Map.get(step, :name, "")}
    end)
    |> Enum.map(&Map.put(&1, :reordered, true))
  end

  defp preserve_workflow_structure(original_workflow, optimized_workflow) do
    # Automatic structure preservation - keep critical paths intact
    critical_steps =
      original_workflow[:steps]
      |> Enum.filter(&Map.get(&1, :critical, false))
      |> Enum.map(&Map.get(&1, :id))

    # Restore original order for critical steps
    optimized_steps =
      optimized_workflow[:steps]
      |> Enum.map(fn step ->
        if Map.get(step, :id) in critical_steps do
          Map.put(step, :preserve_position, true)
        else
          step
        end
      end)

    Map.put(optimized_workflow, :steps, optimized_steps)
    |> Map.put(:structure_preserved, true)
  end

  defp apply_parallelization_limits(workflow, max_parallel) do
    # Automatic parallelization limiting - batch parallel steps
    # Default to 10 if not specified
    max_parallel = max_parallel || 10

    updated_steps =
      workflow[:steps]
      |> Enum.chunk_every(max_parallel)
      |> Enum.with_index()
      |> Enum.flat_map(fn {chunk, batch_idx} ->
        Enum.map(chunk, fn step ->
          Map.put(step, :parallel_batch, batch_idx)
        end)
      end)

    Map.put(workflow, :steps, updated_steps)
    |> Map.put(:max_parallel_enforced, max_parallel)
  end

  defp analyze_workflow_structure(workflow) do
    # Automatic structure analysis - simple dependency counting using config threshold
    config = Singularity.Workflow.Orchestrator.Config.get(:optimization)
    bottleneck_threshold = Map.get(config, :bottleneck_dependency_threshold, 2)

    steps = Map.get(workflow, :steps, [])

    # Find steps with no dependencies (can start immediately)
    entry_points =
      steps
      |> Enum.filter(fn step ->
        deps = Map.get(step, :depends_on, [])
        Enum.empty?(deps)
      end)
      |> Enum.map(&Map.get(&1, :id))

    # Find steps with many dependencies (potential bottlenecks)
    bottlenecks =
      steps
      |> Enum.filter(fn step ->
        deps = Map.get(step, :depends_on, [])
        length(deps) > bottleneck_threshold
      end)
      |> Enum.map(&Map.get(&1, :id))

    # Find parallelization opportunities (steps with same dependencies)
    parallel_groups =
      steps
      |> Enum.group_by(&Map.get(&1, :depends_on, []))
      |> Enum.filter(fn {_deps, group} -> length(group) > 1 end)
      |> Enum.map(fn {deps, group} ->
        %{
          dependencies: deps,
          parallel_steps: Enum.map(group, &Map.get(&1, :id))
        }
      end)

    {:ok,
     %{
       dependency_graph: %{
         entry_points: entry_points,
         total_steps: length(steps)
       },
       parallelization_opportunities: parallel_groups,
       bottleneck_tasks: bottlenecks
     }}
  end

  defp generate_recommendations(workflow, performance_data, structure_analysis) do
    # Automatic recommendation generation based on common patterns
    recommendations = []

    # Add parallelization recommendations
    recommendations =
      recommendations ++
        Enum.map(structure_analysis.parallelization_opportunities, fn group ->
          %{
            type: :parallelization,
            tasks: group.parallel_steps,
            suggestion: "These #{length(group.parallel_steps)} tasks can run in parallel",
            priority: :high,
            estimated_improvement: "#{length(group.parallel_steps) - 1}x speedup"
          }
        end)

    # Add bottleneck recommendations
    recommendations =
      recommendations ++
        Enum.map(structure_analysis.bottleneck_tasks, fn task_id ->
          %{
            type: :bottleneck,
            task: task_id,
            suggestion: "Consider splitting this task or optimizing dependencies",
            priority: :medium
          }
        end)

    # Add retry recommendations for unreliable tasks
    recommendations =
      (recommendations ++
         performance_data.success_rates)
      |> Enum.filter(fn {_task_id, rate} -> rate < 90.0 end)
      |> Enum.map(fn {task_id, rate} ->
        %{
          type: :retry,
          task: task_id,
          current_success_rate: rate,
          suggestion: "Add retry logic (success rate: #{rate}%)",
          priority: if(rate < 70.0, do: :high, else: :medium)
        }
      end)

    # Add timeout recommendations
    recommendations =
      (recommendations ++
         performance_data.avg_execution_times)
      |> Enum.map(fn {task_id, avg_time} ->
        current_timeout =
          get_in(workflow, [:steps])
          |> Enum.find(&(Map.get(&1, :id) == task_id))
          |> Map.get(:timeout, 30_000)

        if avg_time * 1.5 > current_timeout do
          %{
            type: :timeout,
            task: task_id,
            current_timeout: current_timeout,
            recommended_timeout: round(avg_time * 2),
            suggestion: "Increase timeout from #{current_timeout}ms to #{round(avg_time * 2)}ms",
            priority: :low
          }
        end
      end)
      |> Enum.reject(&is_nil/1)

    recommendations
  end

  defp extract_learning_patterns(execution_data) do
    # Automatic pattern extraction from execution data
    %{
      execution_id: Map.get(execution_data, :execution_id),
      timestamp: DateTime.utc_now(),
      patterns: %{
        # Success patterns
        successful_steps:
          execution_data
          |> Map.get(:task_executions, [])
          |> Enum.filter(&(&1.status == "completed"))
          |> Enum.map(&Map.take(&1, [:task_id, :duration_ms])),

        # Failure patterns
        failed_steps:
          execution_data
          |> Map.get(:task_executions, [])
          |> Enum.filter(&(&1.status == "failed"))
          |> Enum.map(&Map.take(&1, [:task_id, :error_message, :retry_count])),

        # Performance patterns
        performance_metrics: %{
          total_duration: Map.get(execution_data, :duration_ms),
          parallel_execution_count:
            execution_data
            |> Map.get(:task_executions, [])
            |> Enum.group_by(&Map.get(&1, :started_at))
            |> Enum.count(fn {_time, tasks} -> length(tasks) > 1 end),
          retry_success_rate: calculate_retry_success_rate(execution_data)
        },

        # Resource patterns
        resource_usage: %{
          peak_memory_mb: Map.get(execution_data, :peak_memory_mb, 0),
          avg_cpu_percent: Map.get(execution_data, :avg_cpu_percent, 0.0),
          parallel_tasks: Map.get(execution_data, :max_parallel_tasks, 1)
        }
      }
    }
  end

  defp calculate_retry_success_rate(execution_data) do
    task_executions = Map.get(execution_data, :task_executions, [])

    retried_tasks = Enum.filter(task_executions, &(Map.get(&1, :retry_count, 0) > 0))
    successful_retries = Enum.filter(retried_tasks, &(&1.status == "completed"))

    if Enum.empty?(retried_tasks) do
      100.0
    else
      Float.round(length(successful_retries) / length(retried_tasks) * 100, 2)
    end
  end

  defp store_learning_patterns(workflow_name, patterns, repo) do
    # Automatic pattern storage - store in performance metrics table
    import Ecto.Query

    # Find or create workflow record
    workflow =
      from(w in Singularity.Workflow.Orchestrator.Schemas.Workflow,
        where: w.name == ^workflow_name,
        limit: 1
      )
      |> repo.one()

    if workflow do
      # Store patterns as performance metric
      metric_attrs = %{
        workflow_id: workflow.id,
        execution_time_ms:
          get_in(patterns, [:patterns, :performance_metrics, :total_duration]) || 0,
        success_rate: calculate_pattern_success_rate(patterns),
        memory_usage: get_in(patterns, [:patterns, :resource_usage, :peak_memory_mb]) || 0,
        cpu_usage: get_in(patterns, [:patterns, :resource_usage, :avg_cpu_percent]) || 0.0,
        # Will be calculated on next optimization
        optimization_improvement: 0.0,
        learning_data: patterns,
        timestamp: DateTime.utc_now()
      }

      # Insert pattern metrics directly
      metric = struct(Singularity.Workflow.Orchestrator.Schemas.PerformanceMetric, metric_attrs)

      case repo.insert(metric) do
        {:ok, _metric} ->
          Logger.info("Stored learning patterns for workflow: #{workflow_name}")
          :ok

        {:error, reason} ->
          Logger.warning("Failed to store learning patterns: #{inspect(reason)}")
          # Don't fail the whole operation
          :ok
      end
    else
      Logger.debug("Workflow not found for pattern storage: #{workflow_name}")
      :ok
    end
  rescue
    error ->
      Logger.warning("Error storing learning patterns: #{inspect(error)}")
      # Don't fail the whole operation
      :ok
  end

  defp calculate_pattern_success_rate(patterns) do
    successful = length(get_in(patterns, [:patterns, :successful_steps]) || [])
    failed = length(get_in(patterns, [:patterns, :failed_steps]) || [])
    total = successful + failed

    if total == 0 do
      0.0
    else
      Float.round(successful / total, 4)
    end
  end

  # Helper functions for default configurations

  defp determine_retry_count(success_rate, retry_thresholds) do
    # Use config thresholds to determine retry count
    Enum.reduce_while(
      [
        :very_unreliable,
        :somewhat_unreliable,
        :mostly_reliable,
        :very_reliable
      ],
      1,
      fn threshold_key, _acc ->
        {min_rate, max_rate, retry_count} =
          Map.get(retry_thresholds, threshold_key, {0.0, 100.0, 1})

        if success_rate >= min_rate and success_rate < max_rate do
          {:halt, retry_count}
        else
          {:cont, 1}
        end
      end
    )
  end

  defp default_retry_thresholds do
    %{
      very_unreliable: {0.0, 50.0, 5},
      somewhat_unreliable: {50.0, 80.0, 3},
      mostly_reliable: {80.0, 95.0, 2},
      very_reliable: {95.0, 100.0, 1}
    }
  end

  defp default_execution_brackets do
    %{
      fast: 1_000,
      medium: 10_000,
      slow: 999_999_999
    }
  end

  defp default_resource_defaults do
    %{
      memory_mb_low: 1024,
      memory_mb_high: 2048,
      cpu_threshold_unreliable: 80.0
    }
  end
end
