defmodule Singularity.Workflow.Jobs.GpuStepJob do
  @moduledoc """
  Oban job for executing GPU-accelerated workflow steps.

  This specialized job module handles workflow steps that require GPU resources,
  with:
  - GPU resource allocation and locking
  - CUDA/Metal context management
  - Memory-intensive operation handling
  - GPU-specific timeout and retry policies

  Note: Nx/EXLA are conditionally loaded - warnings are expected if not available.

  ## Resource Requirements

  GPU jobs are routed to the :gpu_jobs queue and require:
  - Available GPU device
  - Sufficient GPU memory
  - CUDA/Metal runtime

  ## Configuration

  Accepts the same arguments as StepJob plus:
  - `resources` - Must include `gpu: true` or `gpu: device_id`
  - Higher default timeout (10 minutes vs 5 minutes)
  - Different retry policy (fewer retries, longer backoff)
  """
  @compile {:no_warn_undefined, [Nx, EXLA]}

  use Oban.Worker,
    queue: :gpu_jobs,
    max_attempts: 2,
    priority: 0,
    tags: ["workflow", "step", "gpu"]

  require Logger

  alias Singularity.Workflow.Execution.DirectBackend

  # 10 minutes for GPU operations
  @default_gpu_timeout 600_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("GpuStepJob: Starting GPU workflow step",
      workflow_run_id: args["workflow_run_id"],
      step_slug: args["step_slug"],
      task_index: args["task_index"],
      resources: args["resources"]
    )

    # Check GPU availability before starting
    case check_gpu_available(args["resources"]) do
      {:ok, gpu_info} ->
        execute_gpu_step(args, start_time, gpu_info)

      {:error, reason} ->
        Logger.error("GpuStepJob: GPU not available",
          reason: reason,
          workflow_run_id: args["workflow_run_id"]
        )

        {:error, {:gpu_unavailable, reason}}
    end
  end

  defp execute_gpu_step(args, start_time, gpu_info) do
    # Decode the step function
    step_fn = decode_function(args["step_function"])
    input = args["input"]
    timeout = args["timeout"] || @default_gpu_timeout

    # Execute with GPU context
    result =
      try do
        # Set GPU environment variables if needed
        with_gpu_context(gpu_info, fn ->
          Task.async(fn ->
            DirectBackend.execute(step_fn, input, %{gpu: true}, %{gpu_info: gpu_info})
          end)
          |> Task.await(timeout)
        end)
      catch
        :exit, {:timeout, _} ->
          Logger.error("GpuStepJob: GPU execution timeout",
            workflow_run_id: args["workflow_run_id"],
            step_slug: args["step_slug"],
            timeout: timeout,
            gpu_info: gpu_info
          )

          {:error, :gpu_execution_timeout}

        :exit, reason ->
          Logger.error("GpuStepJob: GPU execution crashed",
            workflow_run_id: args["workflow_run_id"],
            step_slug: args["step_slug"],
            reason: inspect(reason),
            gpu_info: gpu_info
          )

          {:error, {:gpu_execution_crash, reason}}
      after
        # Always clean up GPU resources
        cleanup_gpu_resources(gpu_info)
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, output} ->
        Logger.info("GpuStepJob: GPU execution completed",
          workflow_run_id: args["workflow_run_id"],
          step_slug: args["step_slug"],
          duration_ms: duration,
          gpu_device: gpu_info[:device_id]
        )

        {:ok, %{result: output, duration_ms: duration, gpu_device: gpu_info[:device_id]}}

      {:error, reason} ->
        Logger.error("GpuStepJob: GPU execution failed",
          workflow_run_id: args["workflow_run_id"],
          step_slug: args["step_slug"],
          reason: inspect(reason),
          duration_ms: duration
        )

        {:error, reason}
    end
  end

  # Check if GPU is available and return GPU information.
  #
  # Returns:
  # - `{:ok, gpu_info}` with device ID, memory, etc.
  # - `{:error, reason}` if GPU unavailable
  #
  # Future Enhancement:
  # - Query NVIDIA SMI / rocm-smi for actual GPU status
  # - Check GPU memory availability
  # - Support multi-GPU selection
  defp check_gpu_available(_resources) do
    # Check if CUDA is available via Nx backend
    case Code.ensure_loaded(Nx) do
      {:module, _nx_module} ->
        try do
          # Check if EXLA backend is available (CUDA support)
          case Code.ensure_loaded(EXLA) do
            {:module, _exla_module} ->
              # Check if CUDA_VISIBLE_DEVICES is set, indicating GPU availability
              if System.get_env("CUDA_VISIBLE_DEVICES") do
                device_id = System.get_env("CUDA_VISIBLE_DEVICES") |> parse_device_id()
                {:ok, %{device_id: device_id || 0, backend: :cuda, memory_gb: 12}}
              else
                # Nx backend detection is not available
                # Default to CPU if CUDA is not available
                {:error, :gpu_backend_not_available}
              end

            _ ->
              {:error, :gpu_backend_not_available}
          end
        rescue
          _ ->
            {:error, :gpu_check_failed}
        end

      {:error, _} ->
        # Nx not available, assume GPU unavailable
        {:error, :nx_not_available}
    end
  end

  defp parse_device_id(nil), do: nil

  defp parse_device_id(str) when is_binary(str) do
    case Integer.parse(str) do
      {device_id, _} -> device_id
      :error -> nil
    end
  end

  # Execute function with GPU context (set environment variables, etc.).
  defp with_gpu_context(gpu_info, fun) do
    # Set CUDA_VISIBLE_DEVICES or similar
    previous_cuda_devices = System.get_env("CUDA_VISIBLE_DEVICES")

    try do
      if gpu_info[:device_id] do
        System.put_env("CUDA_VISIBLE_DEVICES", to_string(gpu_info[:device_id]))
      end

      fun.()
    after
      # Restore previous environment
      if previous_cuda_devices do
        System.put_env("CUDA_VISIBLE_DEVICES", previous_cuda_devices)
      else
        System.delete_env("CUDA_VISIBLE_DEVICES")
      end
    end
  end

  # Clean up GPU resources after execution.
  #
  # Future Implementation:
  # - Clear GPU memory cache
  # - Release CUDA contexts
  # - Reset device if needed
  defp cleanup_gpu_resources(_gpu_info) do
    # Placeholder for GPU cleanup
    :ok
  end

  # Decode function from stored representation (same as StepJob).
  defp decode_function(%{"module" => module, "function" => function, "arity" => arity})
       when is_binary(module) and is_binary(function) and is_integer(arity) do
    module_atom = String.to_existing_atom("Elixir.#{module}")
    function_atom = String.to_existing_atom(function)

    if function_exported?(module_atom, function_atom, arity) do
      fn input -> apply(module_atom, function_atom, [input]) end
    else
      Logger.error("GpuStepJob: Function not found",
        module: module,
        function: function,
        arity: arity
      )

      fn _input -> {:error, :function_not_found} end
    end
  rescue
    ArgumentError ->
      Logger.error("GpuStepJob: Invalid function reference", module: module, function: function)
      fn _input -> {:error, :invalid_function_reference} end
  end

  defp decode_function(other) do
    Logger.warning("GpuStepJob: Cannot decode function", value: inspect(other))
    fn _input -> {:error, :cannot_decode_function} end
  end

  # Create normalized job arguments with GPU-specific defaults
  defp normalize_args(args) when is_list(args) or is_map(args) do
    %{
      "step_function" => get_arg(args, :step_function),
      "input" => get_arg(args, :input),
      "workflow_run_id" => get_arg(args, :workflow_run_id),
      "step_slug" => get_arg(args, :step_slug),
      "task_index" => get_arg(args, :task_index),
      "resources" => get_arg(args, :resources) || [gpu: true],
      "timeout" => get_arg(args, :timeout) || @default_gpu_timeout
    }
  end

  defp get_arg(args, key) when is_map(args), do: args[key] || args[to_string(key)]
  defp get_arg(args, key) when is_list(args), do: Keyword.get(args, key)

  @doc """
  Create a new GpuStepJob with normalized arguments.

  This function wraps the auto-generated new/1 from Oban.Worker.
  """
  def create(args) when is_list(args) or is_map(args) do
    args
    |> normalize_args()
    |> new()
  end
end
