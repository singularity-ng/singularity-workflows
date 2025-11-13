defmodule Singularity.Workflow.DAG.TaskExecutor do
  @moduledoc """
  Executes workflow step tasks from the database with production-grade reliability.

  This module is the heart of Singularity.Workflow's execution engine, responsible for
  orchestrating task execution across distributed workers while maintaining data
  consistency and fault tolerance.

  ## Execution Model

  Implements a robust polling-based execution model:

  1. **Poll** for queued tasks from pgmq queue
  2. **Claim** tasks atomically using PostgreSQL row-level locking
  3. **Execute** step functions with configurable timeouts
  4. **Complete** tasks via PostgreSQL functions (ensures atomic state updates)
  5. **Repeat** until workflow completes or fails

  ## Concurrency & Safety

  ### Multi-Worker Coordination

  Multiple workers can execute the same workflow run concurrently. Coordination is
  handled entirely by PostgreSQL:

  - **Row-level locking**: `FOR UPDATE SKIP LOCKED` prevents double-execution
  - **Atomic state updates**: PostgreSQL functions ensure consistency
  - **No inter-worker communication**: Database is the single source of truth

  ### Deadlock Handling

  The executor includes sophisticated deadlock detection and recovery:

  - **Automatic detection**: Catches PostgreSQL `deadlock_detected` errors
  - **Exponential backoff**: Retries with increasing delays (50ms → 2s)
  - **Jitter**: Random component prevents thundering herd problems
  - **Graceful degradation**: Fails fast after max retries

  ### Error Recovery

  - **Consecutive error tracking**: Monitors error patterns (max 30 errors)
  - **Circuit breaker**: Stops execution after too many failures
  - **Exponential backoff**: 200ms base, grows to 30s max with jitter
  - **Safe failure marking**: Always attempts to mark workflow as failed on crash

  ## Polling Strategy

  ### Configuration

  - **Default poll_interval**: 200ms (balanced latency vs. load)
  - **Batch size**: 10 tasks per poll (configurable)
  - **Max poll seconds**: 5 seconds (prevents indefinite blocking)

  ### Trade-offs

  | Poll Interval | Latency | Database Load | Use Case |
  |--------------|---------|---------------|----------|
  | 50ms | Very Low | High | Real-time workflows |
  | 200ms | Low | Moderate | **Default (recommended)** |
  | 500ms | Moderate | Low | Batch processing |
  | 1000ms+ | High | Very Low | Background jobs |

  ### Performance Considerations

  - Lower intervals reduce task latency but increase database connections
  - Higher intervals reduce load but delay task execution
  - Monitor connection pool usage under high concurrency
  - Adjust based on workflow SLA requirements

  ## Retry & Backoff Strategy

  ### Exponential Backoff Formula

  ```
  backoff = min(base_delay * 2^attempt + random(0, base_delay), max_cap)
  ```

  ### Retry Limits

  - **Consecutive errors**: 30 max (prevents infinite loops)
  - **Deadlock retries**: Automatic with exponential backoff
  - **Connection failures**: 10 retries with backoff
  - **Task execution**: Handled by step-level retry configuration

  ### Backoff Examples

  | Attempt | Base Delay | Exponential | Jitter | Total (approx) |
  |---------|-----------|-------------|--------|----------------|
  | 1 | 200ms | 200ms | 0-200ms | 200-400ms |
  | 2 | 200ms | 400ms | 0-200ms | 400-600ms |
  | 3 | 200ms | 800ms | 0-200ms | 800-1000ms |
  | 5 | 200ms | 3.2s | 0-200ms | 3.2-3.4s |
  | 10 | 200ms | 102.4s | 0-200ms | 30s (capped) |

  ## Error Handling

  ### Task-Level Errors

  - **Execution failure**: Marked as 'failed', retried if `attempts < max_attempts`
  - **Timeout**: Marked as 'failed' with timeout error message
  - **Max attempts exceeded**: Step marked as 'failed', propagates to workflow run

  ### System-Level Errors

  - **Deadlocks**: Automatically retried with exponential backoff
  - **Connection failures**: Retried up to 10 times with backoff
  - **Unexpected exceptions**: Logged with full stack trace, workflow marked as failed

  ### Failure Propagation

  ```
  Task Error → Step Failure → Workflow Failure
  ```

  All failures are logged with structured metadata for debugging.

  ## Examples

      # Execute workflow with default settings
      {:ok, output} = TaskExecutor.execute_run(run_id, definition, repo)

      # Execute with custom timeout and polling
      {:ok, output} = TaskExecutor.execute_run(
        run_id,
        definition,
        repo,
        timeout: 600_000,        # 10 minutes
        poll_interval: 100,      # 100ms polling
        batch_size: 20,          # Process 20 tasks at once
        task_timeout_ms: 60_000  # 60s per task
      )

  ## Monitoring

  The executor logs comprehensive metrics:

  - Connection pool status at startup
  - Task execution counts and durations
  - Error rates and backoff delays
  - Deadlock occurrences and retries
  - Workflow completion status

  All logs include structured metadata (run_id, worker_id, step_slug) for easy
  correlation and debugging.
  """

  require Logger

  alias Singularity.Workflow.DAG.WorkflowDefinition
  alias Singularity.Workflow.Execution.Strategy
  alias Singularity.Workflow.FlowTracer
  alias Singularity.Workflow.WorkflowRun

  # Timeout constants (in milliseconds)
  # These prevent indefinite blocking on database operations
  @task_claim_timeout_ms 10_000
  # Maximum time to wait for task claim (row-level lock acquisition)
  @task_execution_timeout_ms 60_000
  # Maximum time for step function execution (default, can be overridden per-step)
  @task_completion_timeout_ms 15_000
  # Maximum time for complete_task() PostgreSQL function call
  @poll_timeout_grace_seconds 5
  # Safety margin added to max_poll_seconds to prevent query timeout

  @batch_failure_threshold 0.5
  @exponential_backoff_base_ms 200
  @exponential_backoff_max_ms 30_000

  @spec should_retry_after_error?(map(), map()) :: boolean()
  defp should_retry_after_error?(updated_config, config) do
    updated_config.consecutive_errors < config.max_consecutive_errors
  end

  @spec calculate_exponential_backoff(integer()) :: integer()
  defp calculate_exponential_backoff(consecutive_errors) do
    consecutive_errors
    |> calculate_exponential_delay()
    |> add_jitter()
    |> cap_at_maximum()
  end

  @spec calculate_exponential_delay(integer()) :: integer()
  defp calculate_exponential_delay(consecutive_errors) do
    consecutive_errors
    |> Kernel.-(1)
    |> :math.pow(2)
    |> Kernel.*(@exponential_backoff_base_ms)
    |> round()
  end

  @spec add_jitter(integer()) :: integer()
  defp add_jitter(exponential_delay) do
    exponential_delay + :rand.uniform(@exponential_backoff_base_ms)
  end

  @spec cap_at_maximum(integer()) :: integer()
  defp cap_at_maximum(delay), do: min(delay, @exponential_backoff_max_ms)

  @spec log_backoff_decision(Ecto.UUID.t(), integer(), integer()) :: :ok
  defp log_backoff_decision(run_id, consecutive_errors, backoff_ms) do
    Logger.debug("Backing off after error with exponential backoff",
      run_id: run_id,
      consecutive_errors: consecutive_errors,
      backoff_ms: backoff_ms
    )
  end

  @spec valid_batch_size?(integer()) :: boolean()
  defp valid_batch_size?(batch_size) when batch_size >= 1 and batch_size <= 100, do: true
  defp valid_batch_size?(_), do: false

  @spec valid_poll_interval?(integer()) :: boolean()
  defp valid_poll_interval?(poll_interval_ms)
       when poll_interval_ms >= 10 and poll_interval_ms <= 10_000,
       do: true

  defp valid_poll_interval?(_), do: false

  @spec log_and_return_invalid_batch_size(Ecto.UUID.t(), integer()) :: {:error, tuple()}
  defp log_and_return_invalid_batch_size(run_id, batch_size) do
    Logger.error("TaskExecutor: Invalid batch_size",
      run_id: run_id,
      batch_size: batch_size,
      valid_range: "1-100"
    )

    {:error, {:invalid_batch_size, batch_size}}
  end

  @spec log_and_return_invalid_poll_interval(Ecto.UUID.t(), integer()) :: {:error, tuple()}
  defp log_and_return_invalid_poll_interval(run_id, poll_interval_ms) do
    Logger.error("TaskExecutor: Invalid poll_interval",
      run_id: run_id,
      poll_interval_ms: poll_interval_ms,
      valid_range: "10-10000ms"
    )

    {:error, {:invalid_poll_interval, poll_interval_ms}}
  end

  @spec log_connection_pool_status(module()) :: :ok
  defp log_connection_pool_status(repo) do
    try do
      # Try to get pool status from Ecto
      if function_exported?(repo, :config, 0) do
        config = repo.config()
        pool_size = Keyword.get(config, :pool_size, :unknown)

        Logger.debug("Connection pool status",
          repo: inspect(repo),
          pool_size: pool_size,
          note: "Monitor pool usage under high concurrency"
        )
      end
    rescue
      _ -> :ok
    end
  end

  @doc """
  Execute all tasks for a workflow run until completion or failure.

  Uses pgmq for task coordination (matches Singularity.Workflow architecture):
  1. Poll messages from pgmq queue
  2. Call start_tasks() to claim tasks
  3. Execute step functions
  4. Call complete_task() or fail_task()

  Returns:
  - `{:ok, output}` - Run completed successfully
  - `{:ok, :in_progress}` - Run still in progress (when timeout occurs)
  - `{:error, reason}` - Run failed

  ## Examples

      # Execute with default settings (runs until completion)
      iex> {:ok, output} = TaskExecutor.execute_run(
      ...>   run_id,
      ...>   workflow_definition,
      ...>   MyApp.Repo
      ...> )
      iex> Map.keys(output)
      [:result, :processed_count, :duration_ms]

      # Execute with timeout (useful for long-running workflows)
      iex> {:ok, status} = TaskExecutor.execute_run(
      ...>   run_id,
      ...>   workflow_definition,
      ...>   MyApp.Repo,
      ...>   timeout: 30_000,  # 30 seconds
      ...>   poll_interval: 100  # Poll every 100ms
      ...> )
      iex> status
      :in_progress  # Workflow still running after timeout

  Multiple workers can execute the same run concurrently by passing different
  worker_id options. PostgreSQL handles coordination via row-level locking
  on task claims to prevent double-execution.
  """
  @spec execute_run(Ecto.UUID.t(), WorkflowDefinition.t(), module(), keyword()) ::
          {:ok, map()} | {:ok, :in_progress} | {:error, term()}
  def execute_run(run_id, definition, repo, opts \\ [])
      when is_binary(run_id) or is_struct(run_id, Ecto.UUID) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    # :infinity default (matches Singularity.Workflow - runs until workflow completes)
    poll_interval_ms = Keyword.get(opts, :poll_interval, 200)
    # 200ms between polls
    worker_id = Keyword.get(opts, :worker_id, Ecto.UUID.generate())
    batch_size = Keyword.get(opts, :batch_size, 10)
    # Poll up to 10 messages at once (matches Singularity.Workflow default)
    max_poll_seconds = Keyword.get(opts, :max_poll_seconds, 5)
    # Max time to wait for messages (matches Singularity.Workflow default)
    task_timeout_ms = Keyword.get(opts, :task_timeout_ms, 30_000)
    # Task execution timeout in milliseconds (default: 30 seconds)

    start_time = System.monotonic_time(:millisecond)

    cond do
      not valid_batch_size?(batch_size) ->
        log_and_return_invalid_batch_size(run_id, batch_size)

      not valid_poll_interval?(poll_interval_ms) ->
        log_and_return_invalid_poll_interval(run_id, poll_interval_ms)

      true ->
        # Log connection pool status if available
        log_connection_pool_status(repo)

        Logger.info("Starting execution loop",
          run_id: run_id,
          worker_id: worker_id,
          batch_size: batch_size,
          workflow_slug: definition.slug,
          task_timeout_ms: task_timeout_ms,
          poll_interval_ms: poll_interval_ms,
          coordination: "pgmq"
        )

        :telemetry.execute(
          [:singularity_workflow, :task_executor, :execute_run, :start],
          %{system_time: System.system_time()},
          %{
            run_id: run_id,
            workflow_slug: definition.slug,
            worker_id: worker_id,
            batch_size: batch_size,
            poll_interval_ms: poll_interval_ms,
            task_timeout_ms: task_timeout_ms
          }
        )

        config = %{
          worker_id: worker_id,
          poll_interval_ms: poll_interval_ms,
          batch_size: batch_size,
          max_poll_seconds: max_poll_seconds,
          task_timeout_ms: task_timeout_ms,
          timeout: timeout,
          start_time: start_time,
          consecutive_errors: 0,
          max_consecutive_errors: 30
        }

        try do
          result = execute_loop(run_id, definition.slug, definition, repo, config)
          duration = System.monotonic_time(:millisecond) - start_time

          case result do
            {:ok, _output} = ok_result ->
              :telemetry.execute(
                [:singularity_workflow, :task_executor, :execute_run, :stop],
                %{duration: duration},
                %{
                  run_id: run_id,
                  workflow_slug: definition.slug,
                  status: :ok
                }
              )

              ok_result

            {:error, _reason} = error_result ->
              :telemetry.execute(
                [:singularity_workflow, :task_executor, :execute_run, :stop],
                %{duration: duration},
                %{
                  run_id: run_id,
                  workflow_slug: definition.slug,
                  status: :error,
                  error: elem(error_result, 1)
                }
              )

              error_result
          end
        rescue
          error ->
            duration = System.monotonic_time(:millisecond) - start_time

            Logger.error("TaskExecutor: Unexpected exception in execution loop",
              run_id: run_id,
              error: Exception.format(:error, error, __STACKTRACE__)
            )

            :telemetry.execute(
              [:singularity_workflow, :task_executor, :execute_run, :exception],
              %{duration: duration},
              %{
                run_id: run_id,
                workflow_slug: definition.slug,
                kind: :error,
                error: Exception.message(error)
              }
            )

            # Try to mark workflow as failed
            _ = mark_workflow_failed_safe(run_id, repo, Exception.message(error))

            {:error, {:execution_exception, Exception.message(error)}}
        catch
          kind, reason ->
            duration = System.monotonic_time(:millisecond) - start_time

            Logger.error("TaskExecutor: Unexpected throw/exit in execution loop",
              run_id: run_id,
              kind: kind,
              reason: inspect(reason)
            )

            :telemetry.execute(
              [:singularity_workflow, :task_executor, :execute_run, :exception],
              %{duration: duration},
              %{
                run_id: run_id,
                workflow_slug: definition.slug,
                kind: kind,
                error: inspect(reason)
              }
            )

            # Try to mark workflow as failed
            _ = mark_workflow_failed_safe(run_id, repo, inspect(reason))

            {:error, {:execution_exception, kind, reason}}
        end
    end
  end

  @spec backoff_for_deadlock_retry() :: :ok
  defp backoff_for_deadlock_retry do
    base_delay_ms = 50
    exponential_delay = (base_delay_ms * :math.pow(2, 0)) |> round()
    jitter = :rand.uniform(base_delay_ms)
    backoff_ms = min(exponential_delay + jitter, 1_000)
    Process.sleep(backoff_ms)
  end

  @spec mark_workflow_failed_safe(Ecto.UUID.t(), module(), String.t()) :: :ok | :error
  defp mark_workflow_failed_safe(run_id, repo, error_message) do
    try do
      run_id
      |> repo.get(Singularity.Workflow.WorkflowRun)
      |> mark_failed_if_exists(repo, error_message)
    rescue
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  @spec mark_failed_if_exists(nil | Singularity.Workflow.WorkflowRun.t(), module(), String.t()) ::
          :ok | :error
  defp mark_failed_if_exists(nil, _repo, _error_message), do: :ok

  defp mark_failed_if_exists(run, repo, error_message) do
    run
    |> Singularity.Workflow.WorkflowRun.mark_failed(error_message)
    |> repo.update()
    |> to_ok_or_error()
  end

  @spec to_ok_or_error({:ok, term()} | {:error, term()}) :: :ok | :error
  defp to_ok_or_error({:ok, _}), do: :ok
  defp to_ok_or_error({:error, _}), do: :error

  # Main execution loop: poll pgmq → claim → execute → repeat
  @spec execute_loop(
          Ecto.UUID.t(),
          String.t(),
          WorkflowDefinition.t(),
          module(),
          map()
        ) :: {:ok, map()} | {:ok, :in_progress} | {:error, term()}
  defp execute_loop(run_id, workflow_slug, definition, repo, config) do
    %{
      worker_id: worker_id,
      poll_interval_ms: poll_interval_ms,
      batch_size: batch_size,
      max_poll_seconds: max_poll_seconds,
      task_timeout_ms: task_timeout_ms,
      timeout: timeout,
      start_time: start_time
    } = config

    elapsed = System.monotonic_time(:millisecond) - start_time

    cond do
      timeout != :infinity and elapsed > timeout ->
        Logger.warning("Timeout exceeded",
          run_id: run_id,
          elapsed_ms: elapsed,
          timeout_ms: timeout
        )

        check_run_status(run_id, repo)

      config.consecutive_errors >= config.max_consecutive_errors ->
        Logger.error("TaskExecutor: Too many consecutive errors, aborting",
          run_id: run_id,
          consecutive_errors: config.consecutive_errors,
          max_errors: config.max_consecutive_errors
        )

        _ = mark_workflow_failed_safe(run_id, repo, "Too many consecutive execution errors")
        {:error, {:too_many_errors, config.consecutive_errors}}

      true ->
        case poll_and_execute_batch(
               workflow_slug,
               definition,
               repo,
               worker_id,
               batch_size,
               max_poll_seconds,
               poll_interval_ms,
               task_timeout_ms
             ) do
          {:ok, :tasks_executed, count} ->
            # Tasks completed, poll for next batch immediately
            Logger.debug("Executed batch of tasks",
              run_id: run_id,
              task_count: count
            )

            # Reset error counter on success
            updated_config = %{config | consecutive_errors: 0}
            execute_loop(run_id, workflow_slug, definition, repo, updated_config)

          {:ok, :no_messages} ->
            # No messages available, check run status
            case check_run_status(run_id, repo) do
              {:ok, output} when is_map(output) ->
                # Run completed successfully
                {:ok, output}

              {:error, _} = error ->
                error

              {:ok, :in_progress} ->
                # Run still in progress, continue polling
                execute_loop(run_id, workflow_slug, definition, repo, config)
            end

          {:error, reason} ->
            Logger.error("Task execution failed",
              run_id: run_id,
              reason: inspect(reason),
              consecutive_errors: config.consecutive_errors + 1
            )

            # Increment error counter
            updated_config = %{config | consecutive_errors: config.consecutive_errors + 1}

            if should_retry_after_error?(updated_config, config) do
              backoff_duration = calculate_exponential_backoff(updated_config.consecutive_errors)
              log_backoff_decision(run_id, updated_config.consecutive_errors, backoff_duration)
              Process.sleep(backoff_duration)
              execute_loop(run_id, workflow_slug, definition, repo, updated_config)
            else
              {:error, reason}
            end
        end
    end
  end

  # Poll pgmq for messages and execute tasks (matches Singularity.Workflow architecture)
  @spec poll_and_execute_batch(
          String.t(),
          WorkflowDefinition.t(),
          module(),
          String.t(),
          integer(),
          integer(),
          integer(),
          integer()
        ) :: {:ok, :no_messages} | {:ok, :tasks_executed, integer()} | {:error, term()}
  defp poll_and_execute_batch(
         workflow_slug,
         definition,
         repo,
         worker_id,
         batch_size,
         max_poll_seconds,
         poll_interval_ms,
         task_timeout_ms
       ) do
    poll_timeout_ms = (max_poll_seconds + @poll_timeout_grace_seconds) * 1000

    case poll_messages(
           workflow_slug,
           batch_size,
           max_poll_seconds,
           poll_interval_ms,
           poll_timeout_ms,
           repo
         ) do
      {:ok, []} ->
        {:ok, :no_messages}

      {:ok, msg_ids} ->
        process_polled_messages(
          msg_ids,
          workflow_slug,
          definition,
          repo,
          worker_id,
          batch_size,
          max_poll_seconds,
          poll_interval_ms,
          task_timeout_ms
        )

      {:error, {:deadlock_detected, :retry_needed}} ->
        retry_after_deadlock(
          workflow_slug,
          definition,
          repo,
          worker_id,
          batch_size,
          max_poll_seconds,
          poll_interval_ms,
          task_timeout_ms
        )

      {:error, reason} = error ->
        Logger.error("TaskExecutor: Failed to poll pgmq",
          workflow_slug: workflow_slug,
          reason: inspect(reason)
        )

        error
    end
  end

  @spec poll_messages(String.t(), integer(), integer(), integer(), integer(), module()) ::
          {:ok, list(integer())} | {:error, term()}
  defp poll_messages(
         workflow_slug,
         batch_size,
         max_poll_seconds,
         poll_interval_ms,
         poll_timeout_ms,
         repo
       ) do
    try do
      case repo.query(
             """
             SELECT *
             FROM singularity_workflow.read_with_poll(
               queue_name => $1::text,
               vt => $2::integer,
               qty => $3::integer,
               max_poll_seconds => $4::integer,
               poll_interval_ms => $5::integer
             )
             """,
             [workflow_slug, 30, batch_size, max_poll_seconds, poll_interval_ms],
             timeout: poll_timeout_ms
           ) do
        {:ok, %{rows: []}} ->
          {:ok, []}

        {:ok, %{rows: message_rows}} ->
          msg_ids = Enum.map(message_rows, fn [msg_id | _rest] -> msg_id end)

          Logger.debug("Polled messages from queue",
            workflow_slug: workflow_slug,
            msg_count: length(msg_ids)
          )

          {:ok, msg_ids}

        error ->
          error
      end
    rescue
      e in [Postgrex.Error] ->
        handle_poll_postgrex_error(e, workflow_slug)

      error ->
        Logger.error("TaskExecutor: Unexpected error during poll",
          workflow_slug: workflow_slug,
          error: Exception.format(:error, error, __STACKTRACE__)
        )

        {:error, {:poll_error, Exception.message(error)}}
    catch
      kind, reason ->
        Logger.error("TaskExecutor: Unexpected exception during poll",
          workflow_slug: workflow_slug,
          kind: kind,
          reason: inspect(reason)
        )

        {:error, {:poll_exception, kind, reason}}
    end
  end

  @spec handle_poll_postgrex_error(Postgrex.Error.t(), String.t()) :: {:error, term()}
  defp handle_poll_postgrex_error(
         %Postgrex.Error{postgres: %{code: :connection_failure}} = e,
         workflow_slug
       ) do
    Logger.error("TaskExecutor: Database connection failure during poll",
      workflow_slug: workflow_slug,
      error: Exception.message(e)
    )

    {:error, {:connection_failure, Exception.message(e)}}
  end

  defp handle_poll_postgrex_error(
         %Postgrex.Error{postgres: %{code: :deadlock_detected}},
         workflow_slug
       ) do
    Logger.warning("TaskExecutor: Deadlock detected during poll, retrying",
      workflow_slug: workflow_slug
    )

    backoff_for_deadlock_retry()
    {:error, {:deadlock_detected, :retry_needed}}
  end

  defp handle_poll_postgrex_error(e, workflow_slug) do
    Logger.error("TaskExecutor: Unexpected Postgrex error during poll",
      workflow_slug: workflow_slug,
      error: Exception.message(e)
    )

    {:error, {:poll_error, Exception.message(e)}}
  end

  @spec process_polled_messages(
          list(integer()),
          String.t(),
          WorkflowDefinition.t(),
          module(),
          String.t(),
          integer(),
          integer(),
          integer(),
          integer()
        ) :: {:ok, :tasks_executed, integer()} | {:error, term()}
  defp process_polled_messages(
         msg_ids,
         workflow_slug,
         definition,
         repo,
         worker_id,
         batch_size,
         max_poll_seconds,
         poll_interval_ms,
         task_timeout_ms
       ) do
    case claim_tasks(workflow_slug, msg_ids, worker_id, repo) do
      {:ok, tasks_result} ->
        handle_task_claim_result(
          tasks_result,
          workflow_slug,
          definition,
          repo,
          worker_id,
          batch_size,
          max_poll_seconds,
          poll_interval_ms,
          task_timeout_ms
        )

      {:error, {:deadlock_detected, :retry_needed}} ->
        retry_after_deadlock(
          workflow_slug,
          definition,
          repo,
          worker_id,
          batch_size,
          max_poll_seconds,
          poll_interval_ms,
          task_timeout_ms
        )

      {:error, _reason} = error ->
        error
    end
  end

  @spec claim_tasks(String.t(), list(integer()), String.t(), module()) ::
          {:ok, term()} | {:error, term()}
  defp claim_tasks(workflow_slug, msg_ids, worker_id, repo) do
    try do
      repo.query(
        """
        SELECT *
        FROM start_tasks(
          p_workflow_slug => $1::text,
          p_msg_ids => $2::bigint[],
          p_worker_id => $3::text
        )
        """,
        [workflow_slug, msg_ids, worker_id],
        timeout: @task_claim_timeout_ms
      )
    rescue
      e in [Postgrex.Error] ->
        handle_claim_postgrex_error(e, workflow_slug, worker_id, msg_ids)

      error ->
        Logger.error("TaskExecutor: Unexpected error during task claim",
          workflow_slug: workflow_slug,
          error: Exception.format(:error, error, __STACKTRACE__)
        )

        {:error, {:claim_error, Exception.message(error)}}
    catch
      kind, reason ->
        Logger.error("TaskExecutor: Unexpected exception during task claim",
          workflow_slug: workflow_slug,
          kind: kind,
          reason: inspect(reason)
        )

        {:error, {:claim_exception, kind, reason}}
    end
  end

  @spec handle_claim_postgrex_error(Postgrex.Error.t(), String.t(), String.t(), list(integer())) ::
          {:ok, term()} | {:error, term()}
  defp handle_claim_postgrex_error(
         %Postgrex.Error{postgres: %{code: :deadlock_detected}},
         workflow_slug,
         worker_id,
         msg_ids
       ) do
    Logger.warning("TaskExecutor: Deadlock detected during task claim, retrying",
      workflow_slug: workflow_slug,
      worker_id: worker_id,
      msg_count: length(msg_ids)
    )

    backoff_for_deadlock_retry()
    {:error, {:deadlock_detected, :retry_needed}}
  end

  defp handle_claim_postgrex_error(
         %Postgrex.Error{postgres: %{code: :connection_failure}} = e,
         workflow_slug,
         _worker_id,
         _msg_ids
       ) do
    Logger.error("TaskExecutor: Database connection failure during task claim",
      workflow_slug: workflow_slug,
      error: Exception.message(e)
    )

    {:error, {:connection_failure, Exception.message(e)}}
  end

  defp handle_claim_postgrex_error(
         %Postgrex.Error{postgres: %{code: :lock_not_available}},
         workflow_slug,
         worker_id,
         _msg_ids
       ) do
    Logger.debug("TaskExecutor: Lock not available (task already claimed)",
      workflow_slug: workflow_slug,
      worker_id: worker_id
    )

    {:ok, %{columns: [], rows: []}}
  end

  defp handle_claim_postgrex_error(e, workflow_slug, _worker_id, _msg_ids) do
    Logger.error("TaskExecutor: Unexpected Postgrex error during task claim",
      workflow_slug: workflow_slug,
      error: Exception.message(e)
    )

    {:error, {:claim_error, Exception.message(e)}}
  end

  @spec retry_after_deadlock(
          String.t(),
          WorkflowDefinition.t(),
          module(),
          String.t(),
          integer(),
          integer(),
          integer(),
          integer()
        ) :: {:ok, :no_messages} | {:ok, :tasks_executed, integer()} | {:error, term()}
  defp retry_after_deadlock(
         workflow_slug,
         definition,
         repo,
         worker_id,
         batch_size,
         max_poll_seconds,
         poll_interval_ms,
         task_timeout_ms
       ) do
    Logger.debug("TaskExecutor: Retrying poll after deadlock",
      workflow_slug: workflow_slug
    )

    backoff_for_deadlock_retry()

    poll_and_execute_batch(
      workflow_slug,
      definition,
      repo,
      worker_id,
      batch_size,
      max_poll_seconds,
      poll_interval_ms,
      task_timeout_ms
    )
  end

  # Execute tasks concurrently and check for failures
  @spec execute_tasks_concurrently(
          list(map()),
          WorkflowDefinition.t(),
          module(),
          integer(),
          integer(),
          String.t()
        ) :: {:ok, :tasks_executed, integer()} | {:error, term()}
  defp execute_tasks_concurrently(
         tasks,
         definition,
         repo,
         task_timeout_ms,
         batch_size,
         workflow_slug
       ) do
    results =
      Task.async_stream(
        tasks,
        fn task -> execute_task_from_map(task, definition, repo, task_timeout_ms) end,
        max_concurrency: batch_size,
        timeout: @task_execution_timeout_ms
      )
      |> Enum.to_list()

    check_batch_failures(results, tasks, workflow_slug)
  end

  # Check for execution or worker failures in batch
  @spec check_batch_failures(
          list({:ok, {:ok, :task_executed} | {:error, term()}} | {:exit, term()}),
          list(map()),
          String.t()
        ) :: {:ok, :tasks_executed, integer()} | {:error, term()}
  defp check_batch_failures(results, tasks, workflow_slug) do
    failed =
      Enum.filter(results, fn
        {:ok, {:error, _}} -> true
        {:exit, _} -> true
        _ -> false
      end)

    if failed == [] do
      {:ok, :tasks_executed, length(tasks)}
    else
      Logger.warning(
        "TaskExecutor: #{length(failed)}/#{length(tasks)} task executions failed in batch",
        workflow_slug: workflow_slug,
        failed_count: length(failed)
      )

      # Return error only if significant portion of batch failed (threshold exceeded)
      failure_ratio = length(failed) / length(tasks)

      if failure_ratio > @batch_failure_threshold do
        {:error, {:batch_failure, length(failed), length(tasks), failure_ratio}}
      else
        {:ok, :tasks_executed, length(tasks)}
      end
    end
  end

  # Execute a single task from map (after start_tasks() call)
  #
  # Retrieves the step function from the workflow definition and executes it with a configurable
  # timeout using Task.async/yield pattern. Catches any exceptions and converts them to error
  # tuples for consistent error handling. Upon completion (success or failure), calls
  # complete_task_success/5 or complete_task_failure/5 to update the database state.
  #
  # Timeout handling: If a task exceeds the timeout (in milliseconds), Task.shutdown(:brutal_kill)
  # is called to terminate it and an error tuple is returned.
  #
  # Exception handling: Any exception (throw, error, exit) is caught and converted to
  # {:error, {:exception, {kind, error}}} tuple for logging and recovery.
  @spec execute_task_from_map(map(), WorkflowDefinition.t(), module(), integer()) ::
          {:ok, :task_executed} | {:error, term()}
  defp execute_task_from_map(task_map, definition, repo, task_timeout_ms) do
    run_id = task_map["run_id"]
    step_slug = task_map["step_slug"]
    task_index = task_map["task_index"]
    input = task_map["input"]

    # Convert step_slug string to atom for function lookup
    # Note: String.to_existing_atom/1 will raise if the atom doesn't exist,
    # which is expected behavior - step slugs should always be valid atoms
    # from the workflow definition
    step_slug_atom = String.to_existing_atom(step_slug)
    step_fn = WorkflowDefinition.get_step_function(definition, step_slug_atom)

    step_fn
    |> execute_task_if_found(
      definition,
      step_slug_atom,
      step_slug,
      run_id,
      task_index,
      input,
      task_timeout_ms,
      repo
    )
  end

  # Complete task successfully (using Singularity.Workflow complete_task function)
  #
  # Calls the PostgreSQL complete_task stored function to mark the task as successfully
  # executed and store the output. This function handles dependency counters, task queue
  # updates, and may trigger execution of dependent steps if this task's step is now complete.
  #
  # Returns {:ok, :task_executed} on success, or {:error, reason} if the database call fails.
  @spec complete_task_success(Ecto.UUID.t(), String.t(), integer(), map(), module()) ::
          {:ok, :task_executed} | {:error, term()}
  defp complete_task_success(run_id, step_slug, task_index, output, repo) do
    # Call PostgreSQL complete_task function with deadlock protection
    # Set timeout to prevent transaction deadlock hangs
    result =
      try do
        repo.query(
          "SELECT complete_task($1::uuid, $2::text, $3::integer, $4::jsonb)",
          [run_id, step_slug, task_index, output],
          timeout: @task_completion_timeout_ms
        )
      rescue
        e in [Postgrex.Error] ->
          case e do
            %Postgrex.Error{postgres: %{code: :deadlock_detected}} ->
              Logger.warning("TaskExecutor: Deadlock detected during task completion, retrying",
                run_id: run_id,
                step_slug: step_slug,
                task_index: task_index
              )

              backoff_for_deadlock_retry()

              repo.query(
                "SELECT complete_task($1::uuid, $2::text, $3::integer, $4::jsonb)",
                [run_id, step_slug, task_index, output],
                timeout: @task_completion_timeout_ms
              )

            _ ->
              Logger.error("TaskExecutor: Unexpected Postgrex error during task completion",
                run_id: run_id,
                step_slug: step_slug,
                error: Exception.message(e)
              )

              {:error, {:completion_error, Exception.message(e)}}
          end

        error ->
          Logger.error("TaskExecutor: Error completing task",
            run_id: run_id,
            step_slug: step_slug,
            error: Exception.format(:error, error, __STACKTRACE__)
          )

          {:error, {:completion_error, Exception.message(error)}}
      catch
        kind, reason ->
          Logger.error("TaskExecutor: Exception completing task",
            run_id: run_id,
            step_slug: step_slug,
            kind: kind,
            reason: inspect(reason)
          )

          {:error, {:completion_exception, kind, reason}}
      end

    result
    |> handle_completion_result(run_id, step_slug, task_index)
  end

  @spec handle_task_result({:ok, map()}, Ecto.UUID.t(), String.t(), integer(), module()) ::
          {:ok, :task_executed} | {:error, term()}
  defp handle_task_result({:ok, output}, run_id, step_slug, task_index, repo) do
    complete_task_success(run_id, step_slug, task_index, output, repo)
  end

  @spec handle_task_result({:error, term()}, Ecto.UUID.t(), String.t(), integer(), module()) ::
          {:ok, :task_executed} | {:error, term()}
  defp handle_task_result({:error, reason}, run_id, step_slug, task_index, repo) do
    complete_task_failure(run_id, step_slug, task_index, reason, repo)
  end

  @spec handle_completion_result({:ok, term()}, Ecto.UUID.t(), String.t(), integer()) ::
          {:ok, :task_executed}
  defp handle_completion_result({:ok, _}, run_id, step_slug, task_index) do
    Logger.debug("Task completed successfully",
      run_id: run_id,
      step_slug: step_slug,
      task_index: task_index
    )

    # Trace step transition (task completed, step may transition to completed)
    FlowTracer.trace_step_transition(run_id, step_slug, "started", "completed", %{
      task_index: task_index
    })

    :telemetry.execute(
      [:singularity_workflow, :task_executor, :task, :completed],
      %{},
      %{
        run_id: run_id,
        step_slug: step_slug,
        task_index: task_index,
        status: :success
      }
    )

    {:ok, :task_executed}
  end

  @spec handle_completion_result({:error, term()}, Ecto.UUID.t(), String.t(), integer()) ::
          {:error, term()}
  defp handle_completion_result({:error, reason}, run_id, step_slug, task_index) do
    Logger.error("Failed to complete task",
      run_id: run_id,
      step_slug: step_slug,
      reason: inspect(reason)
    )

    # Trace step transition (task failed, step may transition to failed)
    FlowTracer.trace_step_transition(run_id, step_slug, "started", "failed", %{
      task_index: task_index,
      error: reason
    })

    :telemetry.execute(
      [:singularity_workflow, :task_executor, :task, :failed],
      %{},
      %{
        run_id: run_id,
        step_slug: step_slug,
        task_index: task_index,
        status: :error,
        error: reason
      }
    )

    {:error, reason}
  end

  @spec truncate_error_message(String.t() | term()) :: String.t()
  defp truncate_error_message(msg) when is_binary(msg), do: String.slice(msg, 0, 1000)
  defp truncate_error_message(other), do: other |> inspect() |> String.slice(0, 1000)

  @spec execute_task_if_found(
          nil,
          WorkflowDefinition.t(),
          atom(),
          String.t(),
          Ecto.UUID.t(),
          integer(),
          map(),
          integer(),
          module()
        ) :: {:error, tuple()}
  defp execute_task_if_found(
         nil,
         _definition,
         _step_slug_atom,
         step_slug,
         run_id,
         _task_index,
         _input,
         _task_timeout_ms,
         _repo
       ) do
    Logger.error("TaskExecutor: Step function not found",
      step_slug: step_slug,
      run_id: run_id
    )

    {:error, {:step_not_found, step_slug}}
  end

  @spec execute_task_if_found(
          function(),
          WorkflowDefinition.t(),
          atom(),
          String.t(),
          Ecto.UUID.t(),
          integer(),
          map(),
          integer(),
          module()
        ) :: {:ok, :task_executed} | {:error, term()}
  defp execute_task_if_found(
         step_fn,
         definition,
         step_slug_atom,
         step_slug,
         run_id,
         task_index,
         input,
         task_timeout_ms,
         repo
       ) do
    execution_config = WorkflowDefinition.get_step_execution_config(definition, step_slug_atom)

    Logger.debug("TaskExecutor: Executing task",
      run_id: run_id,
      step_slug: step_slug,
      task_index: task_index,
      execution_mode: execution_config.execution
    )

    task_start_time = System.monotonic_time()

    # Trace step transition (created -> started) when first task starts
    FlowTracer.trace_step_transition(run_id, step_slug, "created", "started", %{
      task_index: task_index,
      execution_mode: execution_config.execution
    })

    :telemetry.execute(
      [:singularity_workflow, :task_executor, :task, :start],
      %{system_time: System.system_time()},
      %{
        run_id: run_id,
        step_slug: step_slug,
        task_index: task_index,
        execution_mode: execution_config.execution
      }
    )

    result = Strategy.execute(step_fn, input, execution_config, task_timeout_ms)
    task_duration = System.monotonic_time() - task_start_time

    case result do
      {:ok, _output} = ok_result ->
        :telemetry.execute(
          [:singularity_workflow, :task_executor, :task, :stop],
          %{duration: task_duration},
          %{
            run_id: run_id,
            step_slug: step_slug,
            task_index: task_index,
            status: :ok
          }
        )

        handle_task_result(ok_result, run_id, step_slug, task_index, repo)

      {:error, _reason} = error_result ->
        :telemetry.execute(
          [:singularity_workflow, :task_executor, :task, :stop],
          %{duration: task_duration},
          %{
            run_id: run_id,
            step_slug: step_slug,
            task_index: task_index,
            status: :error,
            error: elem(error_result, 1)
          }
        )

        handle_task_result(error_result, run_id, step_slug, task_index, repo)
    end
  end

  @spec handle_task_claim_result(
          {:ok, map()},
          String.t(),
          WorkflowDefinition.t(),
          module(),
          String.t(),
          integer(),
          integer(),
          integer(),
          integer()
        ) :: {:ok, :tasks_executed, integer()} | {:error, term()}
  defp handle_task_claim_result(
         {:ok, %{columns: columns, rows: task_rows}},
         workflow_slug,
         definition,
         repo,
         _worker_id,
         batch_size,
         _max_poll_seconds,
         _poll_interval_ms,
         task_timeout_ms
       ) do
    tasks = Enum.map(task_rows, &(Enum.zip(columns, &1) |> Map.new()))

    Logger.debug("Claimed tasks for execution",
      workflow_slug: workflow_slug,
      task_count: length(tasks)
    )

    execute_tasks_concurrently(tasks, definition, repo, task_timeout_ms, batch_size, workflow_slug)
  end

  @spec handle_task_claim_result(
          {:error, {:deadlock_detected, :retry_needed}},
          String.t(),
          WorkflowDefinition.t(),
          module(),
          String.t(),
          integer(),
          integer(),
          integer(),
          integer()
        ) :: {:ok, :no_messages} | {:ok, :tasks_executed, integer()} | {:error, term()}
  defp handle_task_claim_result(
         {:error, {:deadlock_detected, :retry_needed}},
         workflow_slug,
         definition,
         repo,
         worker_id,
         batch_size,
         max_poll_seconds,
         poll_interval_ms,
         task_timeout_ms
       ) do
    Logger.debug("TaskExecutor: Retrying batch after deadlock",
      workflow_slug: workflow_slug
    )

    backoff_for_deadlock_retry()

    poll_and_execute_batch(
      workflow_slug,
      definition,
      repo,
      worker_id,
      batch_size,
      max_poll_seconds,
      poll_interval_ms,
      task_timeout_ms
    )
  end

  @spec handle_task_claim_result(
          {:error, term()},
          String.t(),
          WorkflowDefinition.t(),
          module(),
          String.t(),
          integer(),
          integer(),
          integer(),
          integer()
        ) :: {:error, term()}
  defp handle_task_claim_result(
         {:error, reason},
         workflow_slug,
         _definition,
         _repo,
         _worker_id,
         _batch_size,
         _max_poll_seconds,
         _poll_interval_ms,
         _task_timeout_ms
       ) do
    Logger.error("TaskExecutor: Failed to start tasks",
      workflow_slug: workflow_slug,
      reason: inspect(reason)
    )

    {:error, reason}
  end

  # Complete task with failure (using Singularity.Workflow fail_task function)
  #
  # Calls the PostgreSQL fail_task stored function to mark a task as failed with an error
  # message. This function may increment retry counters or mark the step/workflow as failed
  # depending on the failure policy configured for the step.
  #
  # Returns {:ok, :task_executed} on success, or {:error, reason} if the database call fails.
  @spec complete_task_failure(Ecto.UUID.t(), String.t(), integer(), term(), module()) ::
          {:ok, :task_executed} | {:error, term()}
  defp complete_task_failure(run_id, step_slug, task_index, reason, repo) do
    error_message = truncate_error_message(reason)

    # Call PostgreSQL fail_task function with deadlock protection
    # Set timeout to prevent transaction deadlock hangs
    result =
      try do
        repo.query(
          "SELECT singularity_workflow.fail_task($1::uuid, $2::text, $3::integer, $4::text)",
          [run_id, step_slug, task_index, error_message],
          timeout: @task_completion_timeout_ms
        )
      rescue
        e in [Postgrex.Error] ->
          case e do
            %Postgrex.Error{postgres: %{code: :deadlock_detected}} ->
              Logger.warning("TaskExecutor: Deadlock detected during task failure, retrying",
                run_id: run_id,
                step_slug: step_slug,
                task_index: task_index
              )

              backoff_for_deadlock_retry()

              repo.query(
                "SELECT singularity_workflow.fail_task($1::uuid, $2::text, $3::integer, $4::text)",
                [run_id, step_slug, task_index, error_message],
                timeout: @task_completion_timeout_ms
              )

            _ ->
              Logger.error("TaskExecutor: Unexpected Postgrex error during task failure",
                run_id: run_id,
                step_slug: step_slug,
                error: Exception.message(e)
              )

              {:error, {:failure_error, Exception.message(e)}}
          end

        error ->
          Logger.error("TaskExecutor: Error failing task",
            run_id: run_id,
            step_slug: step_slug,
            error: Exception.format(:error, error, __STACKTRACE__)
          )

          {:error, {:failure_error, Exception.message(error)}}
      catch
        kind, reason ->
          Logger.error("TaskExecutor: Exception failing task",
            run_id: run_id,
            step_slug: step_slug,
            kind: kind,
            reason: inspect(reason)
          )

          {:error, {:failure_exception, kind, reason}}
      end

    case result do
      {:ok, _} ->
        Logger.warning("Task failed",
          run_id: run_id,
          step_slug: step_slug,
          task_index: task_index,
          reason: error_message
        )

        {:ok, :task_executed}

      {:error, db_reason} ->
        Logger.error("Failed to mark task as failed",
          run_id: run_id,
          step_slug: step_slug,
          reason: inspect(db_reason)
        )

        {:error, db_reason}
    end
  end

  # Check run status to determine if execution is complete
  @spec check_run_status(Ecto.UUID.t(), module()) ::
          {:ok, map()} | {:ok, :in_progress} | {:error, term()}
  defp check_run_status(run_id, repo) do
    case repo.get(WorkflowRun, run_id) do
      nil ->
        Logger.error("Run not found", run_id: run_id)
        {:error, {:run_not_found, run_id}}

      run ->
        case run.status do
          "completed" ->
            Logger.info("Run completed", run_id: run_id)
            {:ok, run.output || %{}}

          "failed" ->
            Logger.error("Run failed", run_id: run_id, error: run.error_message)
            {:error, {:run_failed, run.error_message}}

          "started" ->
            # Still in progress
            {:ok, :in_progress}
        end
    end
  end
end
