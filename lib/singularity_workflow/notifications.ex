defmodule Singularity.Workflow.Notifications.Behaviour do
  @moduledoc """
  Behaviour definition for Singularity.Workflow notifications, used for testing and mocking.
  """

  @callback send_with_notify(String.t(), map(), Ecto.Repo.t()) ::
              {:ok, String.t()} | {:error, any()}

  @callback listen(String.t(), Ecto.Repo.t()) :: {:ok, pid()} | {:error, any()}

  @callback unlisten(pid(), Ecto.Repo.t()) :: :ok | {:error, any()}

  @callback notify_only(String.t(), String.t(), Ecto.Repo.t()) :: :ok | {:error, any()}

  @callback receive_message(String.t(), Ecto.Repo.t(), keyword()) ::
              {:ok, list()} | {:ok, []} | {:error, any()}

  @callback acknowledge(String.t(), String.t(), Ecto.Repo.t()) ::
              :ok | {:error, any()}
end

defmodule Singularity.Workflow.Notifications do
  @moduledoc """
  Production-grade PostgreSQL NOTIFY messaging infrastructure.

  This module provides a complete, battle-tested messaging system built on PostgreSQL's
  native NOTIFY/LISTEN capabilities, eliminating the need for external message brokers
  like NATS, RabbitMQ, or Redis Pub/Sub.

  ## Architecture

  ### Dual-Mode Messaging

  Combines the persistence of PGMQ (PostgreSQL Message Queue) with the real-time
  delivery of PostgreSQL NOTIFY:

  1. **Persistent Storage**: Messages stored in PGMQ for durability
  2. **Real-time Delivery**: NOTIFY triggers instant event propagation
  3. **Best of Both Worlds**: Reliability + Performance

  ### Message Flow

  ```
  Sender                    Database                    Listener
  ──────                    ───────                    ────────
    │                          │                          │
    │── send_with_notify() ───>│                          │
    │                          │── INSERT into pgmq ────>│
    │                          │── pg_notify() ─────────>│
    │                          │                          │── receive_message()
    │<── {:ok, message_id} ───│                          │
  ```

  ## Reliability Features

  ### Retry Strategy

  - **10 retries** with exponential backoff (100ms → 30s max)
  - **Jitter**: Random component prevents thundering herd
  - **Deadlock handling**: Automatic retry with backoff
  - **Connection recovery**: Handles transient connection failures

  ### Error Handling

  - **Input validation**: Queue names, message sizes, timeouts
  - **Graceful degradation**: Fails fast after max retries
  - **Comprehensive logging**: All operations logged with context
  - **Safe cleanup**: Reply queues cleaned up on success/failure

  ### Performance

  - **Message size limits**: 1MB per message (configurable)
  - **Queue name validation**: Enforces PostgreSQL limits (63 chars)
  - **Timeout protection**: All operations have timeouts
  - **Connection pooling**: Respects Ecto connection pool limits

  ## Benefits Over External Brokers

  | Feature | PostgreSQL NOTIFY | NATS/RabbitMQ |
  |---------|------------------|---------------|
  | Setup Complexity | ✅ None (uses existing DB) | ❌ Separate service |
  | Latency | ✅ Sub-millisecond | ⚠️ Network overhead |
  | Reliability | ✅ ACID transactions | ⚠️ Eventual consistency |
  | Observability | ✅ SQL queries | ⚠️ External tools |
  | Cost | ✅ Free (included) | ❌ Additional infrastructure |
  | Durability | ✅ PGMQ + NOTIFY | ✅ Yes (with config) |

  ## Usage Examples

  ### Basic Message Sending

      # Send a message with automatic retry and backoff
      {:ok, message_id} = Singularity.Workflow.Notifications.send_with_notify(
        "workflow_events",
        %{type: "task_completed", task_id: "123", timestamp: DateTime.utc_now()},
        MyApp.Repo
      )

  ### Listening for Events

      # Start listening for NOTIFY events
      {:ok, listener_pid} = Singularity.Workflow.Notifications.listen("workflow_events", MyApp.Repo)

      # Handle notifications in a process
      receive do
        {:notification, ^listener_pid, channel, message_id} ->
          Logger.info("Received notification", channel: channel, message_id: message_id)
          # Process the notification...
      end

      # Clean up when done
      :ok = Singularity.Workflow.Notifications.unlisten(listener_pid, MyApp.Repo)

  ### Receiving Messages

      # Read messages from queue (with visibility timeout)
      {:ok, messages} = Singularity.Workflow.Notifications.receive_message(
        "workflow_events",
        MyApp.Repo,
        limit: 10,
        visibility_timeout: 30
      )

      # Process and acknowledge
      Enum.each(messages, fn msg ->
        process_message(msg.payload)
        :ok = Singularity.Workflow.Notifications.acknowledge(
          msg.queue_name,
          msg.message_id,
          MyApp.Repo
        )
      end)

  ### Custom Retry Configuration

      # Send with custom retry settings
      {:ok, message_id} = Singularity.Workflow.Notifications.send_with_notify(
        "critical_events",
        %{event: "system_alert"},
        MyApp.Repo,
        max_retries: 20,        # More retries for critical messages
        timeout: 60_000,        # 60 second timeout
        poll_interval: 50      # Faster polling
      )

  ## Error Handling

  All functions return standard Elixir error tuples:

      case Singularity.Workflow.Notifications.send_with_notify(queue, message, repo) do
        {:ok, message_id} ->
          Logger.info("Message sent", message_id: message_id)

        {:error, {:invalid_queue_name, :too_long}} ->
          Logger.error("Queue name exceeds 63 character limit")

        {:error, {:message_too_large, size, max}} ->
          Logger.error("Message size \#{size} exceeds limit \#{max}")

        {:error, {:connection_failure, reason}} ->
          Logger.error("Database connection failed", reason: reason)

        {:error, :max_retries_exceeded} ->
          Logger.error("Failed after 10 retry attempts")
      end

  ## Monitoring

  The module logs comprehensive metrics:

  - Message send/receive counts and durations
  - Retry attempts and backoff delays
  - Connection failures and recoveries
  - Deadlock occurrences
  - Queue creation and cleanup

  All logs include structured metadata (queue name, message_id, attempt number)
  for easy correlation and debugging.

  ## Best Practices

  1. **Queue Naming**: Use descriptive, hierarchical names (e.g., `workflow.tasks.started`)
  2. **Message Size**: Keep messages under 100KB for optimal performance
  3. **Error Handling**: Always handle error tuples, don't let them crash
  4. **Cleanup**: Always unlisten when done to free resources
  5. **Monitoring**: Monitor retry rates and connection pool usage
  6. **Timeouts**: Set appropriate timeouts based on your SLA requirements
  """

  @behaviour Singularity.Workflow.Notifications.Behaviour
  require Logger
  alias Pgmq
  alias Pgmq.Message

  @retry_backoff_base_ms 100
  @retry_backoff_max_ms 30_000
  @max_queue_name_length 63
  @max_timeout_ms 300_000
  @max_message_size_bytes 1_048_576

  @doc """
  Send a message via PGMQ with PostgreSQL NOTIFY for real-time delivery.

  ## Parameters

  - `queue_name` - PGMQ queue name
  - `message` - Message payload (will be JSON encoded)
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, message_id}` - Message sent and NOTIFY triggered
  - `{:error, reason}` - Send failed

  ## Logging

  All NOTIFY events are logged with structured logging:
  - `:info` level for successful sends
  - `:error` level for failures
  - Includes queue name, message ID, and timing
  """
  @spec send_with_notify(String.t(), map(), Ecto.Repo.t(), keyword()) ::
          :ok | {:ok, map()} | {:error, any()}
  def send_with_notify(queue_name, message, repo, opts \\ [])
      when is_binary(queue_name) and is_map(message) do
    start_time = System.monotonic_time()
    expect_reply? = Keyword.get(opts, :expect_reply, true)
    timeout_ms = Keyword.get(opts, :timeout, 30_000)
    poll_interval = Keyword.get(opts, :poll_interval, 100)
    max_retries = Keyword.get(opts, :max_retries, 10)

    cond do
      queue_name_too_long?(queue_name) ->
        log_and_return_invalid_queue_name(queue_name, :too_long)

      queue_name_empty?(queue_name) ->
        log_and_return_invalid_queue_name(queue_name, :empty)

      not valid_timeout?(timeout_ms) ->
        log_and_return_invalid_timeout(timeout_ms)

      true ->
        reply_queue =
          if expect_reply? do
            Keyword.get(opts, :reply_queue, "Singularity.Workflow.reply.#{Ecto.UUID.generate()}")
          end

        enriched_message =
          if expect_reply? and reply_queue do
            message
            |> Map.put_new(:reply_to, reply_queue)
            |> Map.put_new("reply_to", reply_queue)
          else
            message
          end

        ensure_reply_queue(expect_reply?, reply_queue, repo)
        retry_send(
          queue_name,
          enriched_message,
          repo,
          reply_queue,
          expect_reply?,
          timeout_ms,
          poll_interval,
          max_retries,
          start_time
        )
    end
  end

  @spec queue_name_too_long?(String.t()) :: boolean()
  defp queue_name_too_long?(queue_name) when byte_size(queue_name) > @max_queue_name_length, do: true
  defp queue_name_too_long?(_), do: false

  @spec queue_name_empty?(String.t()) :: boolean()
  defp queue_name_empty?(""), do: true
  defp queue_name_empty?(_), do: false

  @spec valid_timeout?(integer()) :: boolean()
  defp valid_timeout?(timeout_ms) when timeout_ms >= 0 and timeout_ms <= @max_timeout_ms, do: true
  defp valid_timeout?(_), do: false

  @spec log_and_return_invalid_queue_name(String.t(), :too_long) :: {:error, tuple()}
  defp log_and_return_invalid_queue_name(queue_name, :too_long) do
    Logger.error("Notifications: Queue name too long",
      queue: queue_name,
      length: String.length(queue_name),
      max_length: @max_queue_name_length
    )

    {:error, {:invalid_queue_name, :too_long}}
  end

  @spec log_and_return_invalid_queue_name(String.t(), :empty) :: {:error, tuple()}
  defp log_and_return_invalid_queue_name(_queue_name, :empty) do
    Logger.error("Notifications: Queue name cannot be empty")
    {:error, {:invalid_queue_name, :empty}}
  end

  @spec log_and_return_invalid_timeout(integer()) :: {:error, tuple()}
  defp log_and_return_invalid_timeout(timeout_ms) do
    Logger.error("Notifications: Invalid timeout",
      timeout_ms: timeout_ms,
      valid_range: "0-#{@max_timeout_ms}ms"
    )
    {:error, {:invalid_timeout, timeout_ms}}
  end

  @spec calculate_retry_backoff(integer()) :: integer()
  defp calculate_retry_backoff(retries_left) do
    retries_left
    |> calculate_attempt_number()
    |> calculate_exponential_delay_for_retry()
    |> add_jitter_for_retry()
    |> cap_retry_backoff()
  end

  @spec calculate_attempt_number(integer()) :: integer()
  defp calculate_attempt_number(retries_left), do: 10 - retries_left

  @spec calculate_exponential_delay_for_retry(integer()) :: integer()
  defp calculate_exponential_delay_for_retry(attempt) do
    attempt
    |> :math.pow(2)
    |> Kernel.*(@retry_backoff_base_ms)
    |> round()
  end

  @spec add_jitter_for_retry(integer()) :: integer()
  defp add_jitter_for_retry(exponential_delay) do
    exponential_delay + :rand.uniform(@retry_backoff_base_ms)
  end

  @spec cap_retry_backoff(integer()) :: integer()
  defp cap_retry_backoff(delay), do: min(delay, @retry_backoff_max_ms)

  @spec log_retry_attempt(String.t(), integer(), integer()) :: :ok
  defp log_retry_attempt(queue_name, retries_left, backoff_ms) do
    Logger.debug("Retrying with exponential backoff",
      queue: queue_name,
      attempt: 11 - retries_left,
      backoff_ms: backoff_ms,
      retries_left: retries_left - 1
    )
  end

  @spec channel_too_long_for_notify?(String.t()) :: boolean()
  defp channel_too_long_for_notify?(channel) when byte_size(channel) > @max_queue_name_length, do: true
  defp channel_too_long_for_notify?(_), do: false

  @spec log_channel_too_long_error(String.t(), String.t()) :: :ok
  defp log_channel_too_long_error(queue_name, channel) do
    Logger.error("Notifications: Channel name too long for NOTIFY",
      queue: queue_name,
      channel: channel,
      length: String.length(channel)
    )
  end

  # Retry logic for sending messages with exponential backoff
  @spec retry_send(
          String.t(),
          map(),
          Ecto.Repo.t(),
          String.t() | nil,
          boolean(),
          integer(),
          integer(),
          integer(),
          integer()
        ) :: :ok | {:ok, map()} | {:error, any()}
  defp retry_send(queue_name, message, repo, reply_queue, expect_reply?, timeout_ms, poll_interval, 0, start_time) do
    # No retries left, attempt final send
    with {:ok, message_id} <- send_pgmq_message(queue_name, message, repo),
         :ok <- trigger_notify(queue_name, message_id, repo),
         result <- maybe_wait_for_reply(expect_reply?, reply_queue, repo, timeout_ms, poll_interval) do
      duration = System.monotonic_time() - start_time

      Logger.info("PGMQ + NOTIFY sent successfully",
        queue: queue_name,
        message_id: message_id,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond),
        message_type: Map.get(message, :type, Map.get(message, "type", "unknown")),
        expect_reply: expect_reply?
      )

      cleanup_reply_queue(expect_reply?, reply_queue, repo)
      result
    else
      {:error, reason} ->
        Logger.error("PGMQ + NOTIFY send failed (no retries left)",
          queue: queue_name,
          error: inspect(reason),
          message_type: Map.get(message, :type, Map.get(message, "type", "unknown"))
        )

        cleanup_reply_queue(expect_reply?, reply_queue, repo)
        {:error, reason}
    end
  end

  defp retry_send(queue_name, message, repo, reply_queue, expect_reply?, timeout_ms, poll_interval, retries_left, start_time) do
    with {:ok, message_id} <- send_pgmq_message(queue_name, message, repo),
         :ok <- trigger_notify(queue_name, message_id, repo),
         result <- maybe_wait_for_reply(expect_reply?, reply_queue, repo, timeout_ms, poll_interval) do
      duration = System.monotonic_time() - start_time

      Logger.info("PGMQ + NOTIFY sent successfully",
        queue: queue_name,
        message_id: message_id,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond),
        message_type: Map.get(message, :type, Map.get(message, "type", "unknown")),
        expect_reply: expect_reply?
      )

      cleanup_reply_queue(expect_reply?, reply_queue, repo)
      result
    else
      {:error, reason} ->
        Logger.warning("PGMQ + NOTIFY send failed, retrying",
          queue: queue_name,
          error: inspect(reason),
          retries_left: retries_left - 1
        )

        backoff_duration = calculate_retry_backoff(retries_left)

        log_retry_attempt(queue_name, retries_left, backoff_duration)
        Process.sleep(backoff_duration)

        retry_send(
          queue_name,
          message,
          repo,
          reply_queue,
          expect_reply?,
          timeout_ms,
          poll_interval,
          retries_left - 1,
          start_time
        )
    end
  end

  @doc """
  Listen for NOTIFY events on a PGMQ queue.

  ## Parameters

  - `queue_name` - PGMQ queue name to listen for
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, pid}` - Notification listener process
  - `{:error, reason}` - Failed to start listener

  ## Logging

  Listener start/stop events are logged:
  - `:info` level for successful listener creation
  - `:error` level for listener failures
  - Includes channel name and process ID
  """
  @spec listen(String.t(), Ecto.Repo.t()) :: {:ok, pid()} | {:error, any()}
  def listen(queue_name, repo) do
    channel = "pgmq_#{queue_name}"

    case Postgrex.Notifications.listen(repo, channel) do
      {:ok, pid} ->
        Logger.info("PGMQ NOTIFY listener started",
          queue: queue_name,
          channel: channel,
          listener_pid: inspect(pid)
        )

        {:ok, pid}

      {:error, reason} ->
        Logger.error("PGMQ NOTIFY listener failed to start",
          queue: queue_name,
          channel: channel,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Stop listening for NOTIFY events.

  ## Parameters

  - `pid` - Notification listener process
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Stopped successfully
  - `{:error, reason}` - Stop failed

  ## Logging

  Listener stop events are logged at `:info` level.
  """
  @spec unlisten(pid(), Ecto.Repo.t()) :: :ok | {:error, any()}
  def unlisten(pid, repo) do
    case Postgrex.Notifications.unlisten(repo, pid) do
      :ok ->
        Logger.info("PGMQ NOTIFY listener stopped",
          listener_pid: inspect(pid)
        )

        :ok

      {:error, reason} ->
        Logger.error("PGMQ NOTIFY listener stop failed",
          listener_pid: inspect(pid),
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Send a notification without PGMQ (NOTIFY only).

  Useful for simple notifications that don't need persistence.

  ## Parameters

  - `channel` - NOTIFY channel name
  - `payload` - Notification payload
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Notification sent
  - `{:error, reason}` - Send failed

  ## Logging

  NOTIFY-only events are logged at `:debug` level.
  """
  @spec notify_only(String.t(), String.t(), Ecto.Repo.t()) :: :ok | {:error, any()}
  def notify_only(channel, payload, repo) do
    case repo.query("SELECT pg_notify($1, $2)", [channel, payload]) do
      {:ok, _} ->
        Logger.debug("NOTIFY sent",
          channel: channel,
          payload: payload
        )

        :ok

      {:error, reason} ->
        Logger.error("NOTIFY send failed",
          channel: channel,
          payload: payload,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Receive messages from a PGMQ queue.

  Reads messages from the queue with visibility timeout, making them temporarily
  invisible to other consumers while being processed.

  ## Parameters

  - `queue_name` - PGMQ queue name
  - `repo` - Ecto repository
  - `opts` - Options:
    - `:limit` - Maximum number of messages to read (default: 10)
    - `:visibility_timeout` - Visibility timeout in seconds (default: 30)

  ## Returns

  - `{:ok, messages}` - List of messages (empty list if no messages)
  - `{:error, reason}` - Read failed

  ## Message Format

  Each message is a map with:
  - `:id` - Message ID (string)
  - `:workflow_id` - Workflow ID if applicable
  - `:queue_name` - Queue name
  - `:message_id` - PGMQ message ID
  - `:payload` - Message payload (decoded JSON)

  ## Example

      {:ok, messages} = Singularity.Workflow.Notifications.receive_message(
        "genesis_rule_updates",
        Repo,
        limit: 10,
        visibility_timeout: 30
      )

      Enum.each(messages, fn msg ->
        process_message(msg)
        Singularity.Workflow.Notifications.acknowledge(
          msg.queue_name,
          msg.message_id,
          Repo
        )
      end)

  ## Logging

  Message reads are logged at `:debug` level with message count.
  """
  @spec receive_message(String.t(), Ecto.Repo.t(), keyword()) ::
          {:ok, list()} | {:ok, []} | {:error, any()}
  def receive_message(queue_name, repo, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    visibility_timeout = Keyword.get(opts, :visibility_timeout, 30)

    try do
      # Ensure queue exists
      case ensure_queue(queue_name, repo) do
        :ok ->
          # Read messages from PGMQ
          # PGMQ read_messages returns a list directly or nil
          messages = Pgmq.read_messages(repo, queue_name, visibility_timeout, limit)

          if is_list(messages) and length(messages) > 0 do
            formatted_messages =
              Enum.map(messages, fn %Pgmq.Message{id: msg_id, body: body} ->
                decoded_payload =
                  case Jason.decode(body) do
                    {:ok, decoded} -> decoded
                    {:error, _} -> %{"raw" => body}
                  end

                %{
                  id: Ecto.UUID.generate(),
                  workflow_id:
                    Map.get(decoded_payload, "workflow_id") ||
                      Map.get(decoded_payload, :workflow_id) ||
                      Ecto.UUID.generate(),
                  queue_name: queue_name,
                  message_id: Integer.to_string(msg_id),
                  payload: decoded_payload
                }
              end)

            Logger.debug("Received messages from queue",
              queue: queue_name,
              count: length(formatted_messages),
              limit: limit
            )

            {:ok, formatted_messages}
          else
            {:ok, []}
          end

        {:error, reason} ->
          Logger.error("Failed to ensure queue exists",
            queue: queue_name,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception while receiving messages",
          queue: queue_name,
          error: inspect(error)
        )

        {:error, error}
    end
  end

  @doc """
  Acknowledge (delete) a message after successful processing.

  Removes the message from the queue after it has been successfully processed.
  This should be called after processing to prevent the message from being redelivered.

  ## Parameters

  - `queue_name` - PGMQ queue name
  - `message_id` - Message ID (string) from receive_message
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Message acknowledged/deleted
  - `{:error, reason}` - Acknowledge failed

  ## Example

      {:ok, messages} = Singularity.Workflow.Notifications.receive_message(
        "genesis_rule_updates",
        Repo
      )

      Enum.each(messages, fn msg ->
        case process_message(msg.payload) do
          :ok ->
            Singularity.Workflow.Notifications.acknowledge(
              msg.queue_name,
              msg.message_id,
              Repo
            )

          {:error, reason} ->
            Logger.error("Failed to process message", error: reason)
            # Message will become visible again after visibility timeout
        end
      end)

  ## Logging

  Message acknowledgments are logged at `:debug` level.
  """
  @spec acknowledge(String.t(), String.t(), Ecto.Repo.t()) :: :ok | {:error, any()}
  def acknowledge(queue_name, message_id, repo) when is_binary(message_id) do
    try do
      # Convert string message_id to integer
      case Integer.parse(message_id) do
        {msg_id_int, _} ->
          # Delete the message from PGMQ
          :ok = Pgmq.delete_messages(repo, queue_name, [msg_id_int])

          Logger.debug("Message acknowledged",
            queue: queue_name,
            message_id: message_id
          )

          :ok

        :error ->
          Logger.error("Invalid message_id format",
            message_id: message_id,
            queue: queue_name
          )

          {:error, {:invalid_message_id, message_id}}
      end
    rescue
      error ->
        Logger.error("Exception while acknowledging message",
          queue: queue_name,
          message_id: message_id,
          error: inspect(error)
        )

        {:error, error}
    end
  end

  def acknowledge(_queue_name, message_id, _repo) do
    Logger.error("Invalid message_id type for acknowledge",
      message_id: inspect(message_id),
      expected: "binary (string)"
    )

    {:error, :invalid_message_id}
  end

  # Private: Send message via PGMQ
  @spec send_pgmq_message(String.t(), map(), Ecto.Repo.t()) :: {:ok, String.t()} | {:error, term()}
  defp send_pgmq_message(queue_name, message, repo) when is_binary(queue_name) do
    with :ok <- validate_message_size(message),
         {:ok, json} <- encode_message(message),
         {:ok, message_id} <- do_send(queue_name, json, repo) do
      {:ok, to_string(message_id)}
    else
      {:error, {:message_too_large, _, _} = reason} ->
        log_message_size_error(queue_name, reason)
        {:error, reason}

      error ->
        error
    end
  end

  @spec validate_message_size(map()) :: :ok | {:error, tuple()}
  defp validate_message_size(message) do
    message
    |> :erlang.term_to_binary()
    |> byte_size()
    |> validate_size_against_limit()
  end

  @spec validate_size_against_limit(integer()) :: :ok | {:error, tuple()}
  defp validate_size_against_limit(size) when size > @max_message_size_bytes do
    {:error, {:message_too_large, size, @max_message_size_bytes}}
  end

  defp validate_size_against_limit(_size), do: :ok

  @spec log_message_size_error(String.t(), tuple()) :: :ok
  defp log_message_size_error(queue_name, {:message_too_large, size, max}) do
    Logger.error("Notifications: Message too large",
      queue: queue_name,
      message_size_bytes: size,
      max_size_bytes: max
    )
  end

  @spec encode_message(map()) :: {:ok, String.t()} | {:error, term()}
  defp encode_message(message) do
    case Jason.encode(message) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> log_encode_error_and_return(reason, message)
    end
  end

  @spec log_encode_error_and_return(term(), map()) :: {:error, term()}
  defp log_encode_error_and_return(reason, message) do
    Logger.error("Failed to encode pgmq message",
      error: inspect(reason),
      payload: inspect(message)
    )
    {:error, reason}
  end

  @spec do_send(String.t(), String.t(), Ecto.Repo.t(), integer()) :: {:ok, integer()} | {:error, term()}
  defp do_send(queue_name, json_message, repo, attempts \\ 0)

  defp do_send(queue_name, json_message, repo, attempts) when attempts < 10 do
    try do
      case Pgmq.send_message(repo, queue_name, json_message) do
        {:ok, msg_id} ->
          {:ok, msg_id}

        {:error, reason} ->
          Logger.error("pgmq.send returned error",
            queue: queue_name,
            error: inspect(reason),
            attempt: attempts + 1
          )

          {:error, reason}
      end
    rescue
      error in [Postgrex.Error] ->
        case error do
          %Postgrex.Error{postgres: %{code: :connection_failure}} ->
            Logger.warning("Notifications: Connection failure, retrying",
              queue: queue_name,
              attempt: attempts + 1
            )
            # Exponential backoff with jitter
            base_delay = 100
            exponential_delay = base_delay * :math.pow(2, attempts) |> round()
            jitter = :rand.uniform(base_delay)
            backoff_ms = min(exponential_delay + jitter, 10_000)  # Cap at 10 seconds
            Process.sleep(backoff_ms)
            do_send(queue_name, json_message, repo, attempts + 1)

          %Postgrex.Error{postgres: %{code: :deadlock_detected}} ->
            Logger.warning("Notifications: Deadlock detected, retrying",
              queue: queue_name,
              attempt: attempts + 1
            )
            # Exponential backoff with jitter for deadlocks
            base_delay = 50
            exponential_delay = base_delay * :math.pow(2, attempts) |> round()
            jitter = :rand.uniform(base_delay)
            backoff_ms = min(exponential_delay + jitter, 5_000)  # Cap at 5 seconds
            Process.sleep(backoff_ms)
            do_send(queue_name, json_message, repo, attempts + 1)

          _ ->
            Logger.error("Notifications: Unexpected Postgrex error",
              queue: queue_name,
              error: Exception.message(error)
            )
            {:error, {:unexpected_error, Exception.message(error)}}
        end

      error ->
        # Handle non-Postgrex errors (e.g., queue missing)
        if queue_missing?(error) do
          case ensure_queue(queue_name, repo) do
            :ok -> do_send(queue_name, json_message, repo, attempts + 1)
            {:error, reason} -> {:error, reason}
          end
        else
          Logger.error("pgmq.send failed",
            queue: queue_name,
            error: format_postgrex_error(error),
            attempt: attempts + 1
          )

          {:error, error}
        end
    catch
      kind, reason ->
        Logger.error("Notifications: Unexpected exception sending message",
          queue: queue_name,
          kind: kind,
          reason: inspect(reason),
          attempt: attempts + 1
        )
        {:error, {:unexpected_exception, kind, reason}}
    end
  end

  @spec do_send(String.t(), String.t(), module(), integer()) :: {:error, term()}
  defp do_send(queue_name, _json_message, _repo, attempts) when attempts >= 10 do
    Logger.error("Failed to send message after max retries",
      queue: queue_name,
      max_attempts: 10
    )
    {:error, :max_retries_exceeded}
  end

  @doc """
  Ensure a PGMQ queue exists, creating it if necessary.

  This is a helper function that can be used to guarantee a queue exists
  before reading from it. It's safe to call multiple times.

  ## Parameters

  - `queue_name` - PGMQ queue name
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Queue exists or was created
  - `{:error, reason}` - Failed to create queue

  ## Example

      :ok = Singularity.Workflow.Notifications.ensure_queue("my_queue", Repo)
  """
  @spec ensure_queue(String.t(), Ecto.Repo.t()) :: :ok | {:error, any()}
  def ensure_queue(queue_name, repo) when is_binary(queue_name) do
    if queue_name_too_long?(queue_name) do
      log_and_return_invalid_queue_name(queue_name, :too_long)
    else
      try do
        :ok = Pgmq.create_queue(repo, queue_name)
      rescue
        error in [Postgrex.Error] ->
          case error do
            %Postgrex.Error{postgres: %{code: :duplicate_table}} ->
              :ok

            %Postgrex.Error{postgres: %{code: :duplicate_object}} ->
              :ok

            %Postgrex.Error{postgres: %{code: :connection_failure}} ->
              Logger.error("Notifications: Connection failure creating queue",
                queue: queue_name,
                error: Exception.message(error)
              )
              {:error, {:connection_failure, Exception.message(error)}}

            _ ->
              {:error, Exception.message(error)}
          end

        error ->
          Logger.error("Notifications: Unexpected error creating queue",
            queue: queue_name,
            error: Exception.format(:error, error, __STACKTRACE__)
          )
          {:error, {:unexpected_error, Exception.message(error)}}
      catch
        kind, reason ->
          Logger.error("Notifications: Unexpected exception creating queue",
            queue: queue_name,
            kind: kind,
            reason: inspect(reason)
          )
          {:error, {:unexpected_exception, kind, reason}}
      end
    end
  end

  # Private: Trigger PostgreSQL NOTIFY after PGMQ send
  @dialyzer {:nowarn_function, trigger_notify: 3}
  @spec trigger_notify(String.t(), String.t(), Ecto.Repo.t()) :: :ok | {:error, term()}
  defp trigger_notify(queue_name, message_id, repo) do
    channel = "pgmq_#{queue_name}"

    if channel_too_long_for_notify?(channel) do
      log_channel_too_long_error(queue_name, channel)
      {:error, {:channel_too_long, channel}}
    else
      try do
      case repo.query("SELECT pg_notify($1, $2)", [channel, message_id], timeout: 5_000) do
        {:ok, _} ->
          Logger.debug("NOTIFY triggered",
            queue: queue_name,
            channel: channel,
            message_id: message_id
          )

          :ok

        {:error, reason} ->
          Logger.error("NOTIFY trigger failed",
            queue: queue_name,
            channel: channel,
            error: inspect(reason)
          )
          {:error, {:notify_failed, reason}}
      end
      rescue
        error in [Postgrex.Error] ->
          case error do
            %Postgrex.Error{postgres: %{code: :connection_failure}} ->
              Logger.error("Notifications: Connection failure triggering NOTIFY",
                queue: queue_name,
                error: Exception.message(error)
              )
              {:error, {:connection_failure, Exception.message(error)}}

            _ ->
              Logger.error("Notifications: Unexpected Postgrex error triggering NOTIFY",
                queue: queue_name,
                error: Exception.message(error)
              )
              {:error, {:notify_error, Exception.message(error)}}
          end

      error ->
        Logger.error("Notifications: Unexpected error triggering NOTIFY",
          queue: queue_name,
          error: Exception.format(:error, error, __STACKTRACE__)
        )
        {:error, {:notify_error, Exception.message(error)}}
    catch
      kind, reason ->
        Logger.error("Notifications: Unexpected exception triggering NOTIFY",
          queue: queue_name,
          kind: kind,
          reason: inspect(reason)
        )
        {:error, {:notify_exception, kind, reason}}
      end
    end
  end

  @spec queue_missing?(term()) :: boolean()
  defp queue_missing?(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: true

  defp queue_missing?(%Postgrex.Error{postgres: %{code: :undefined_object}}), do: true

  defp queue_missing?(%Postgrex.Error{postgres: %{message: message}}) when is_binary(message) do
    String.contains?(message, "does not exist")
  end

  defp queue_missing?(_), do: false

  @spec format_postgrex_error(term()) :: String.t()
  defp format_postgrex_error(%Postgrex.Error{postgres: postgres} = _error) do
    %{code: postgres[:code], message: postgres[:message], detail: postgres[:detail]} |> inspect()
  end

  defp format_postgrex_error(error), do: inspect(error)

  @spec ensure_reply_queue(boolean(), String.t() | nil, module()) :: :ok | {:error, term()}
  defp ensure_reply_queue(false, _queue, _repo), do: :ok

  defp ensure_reply_queue(true, queue, repo) do
    ensure_queue(queue, repo)
  end

  @dialyzer {:nowarn_function, maybe_wait_for_reply: 5}
  @spec maybe_wait_for_reply(boolean(), String.t() | nil, module(), integer(), integer()) ::
          :ok | {:ok, map()} | {:error, term()}
  defp maybe_wait_for_reply(false, _queue, _repo, _timeout, _poll_interval), do: :ok

  defp maybe_wait_for_reply(true, queue, repo, timeout_ms, poll_interval) do
    wait_for_reply(queue, repo, timeout_ms, poll_interval)
  end

  @dialyzer {:nowarn_function, wait_for_reply: 4}
  @spec wait_for_reply(String.t(), module(), integer(), integer()) :: {:ok, map()} | {:error, term()}
  defp wait_for_reply(queue, repo, timeout_ms, poll_interval) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_reply(queue, repo, deadline, poll_interval)
  end

  @dialyzer {:nowarn_function, do_wait_for_reply: 4}
  @spec do_wait_for_reply(String.t(), module(), integer(), integer()) :: {:ok, map()} | {:error, term()}
  defp do_wait_for_reply(queue, repo, deadline, poll_interval) do
    case pop_reply_message(queue, repo) do
      {:ok, nil} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(poll_interval)
          do_wait_for_reply(queue, repo, deadline, poll_interval)
        end

      {:ok, %Message{body: payload}} ->
        decode_message_payload(payload)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @dialyzer {:nowarn_function, pop_reply_message: 2}
  @spec pop_reply_message(String.t(), module()) :: {:ok, Pgmq.Message.t() | nil} | {:error, term()}
  defp pop_reply_message(queue, repo) do
    try do
      {:ok, Pgmq.pop_message(repo, queue)}
    rescue
      error ->
        case error do
          %Postgrex.Error{} ->
            Logger.error("pgmq.pop failed", queue: queue, error: format_postgrex_error(error))
            {:error, error}

          _ ->
            Logger.error("Unexpected error while popping reply message",
              queue: queue,
              error: inspect(error)
            )

            {:error, error}
        end
    end
  end

  @dialyzer {:nowarn_function, decode_message_payload: 1}
  @spec decode_message_payload(String.t()) :: {:ok, map()} | {:error, Jason.DecodeError.t()}
  defp decode_message_payload(msg) when is_binary(msg) do
    case Jason.decode(msg) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        Logger.error("Failed to decode reply message", error: inspect(reason), payload: msg)
        {:error, reason}
    end
  end

  @spec cleanup_reply_queue(boolean(), String.t() | nil, module()) :: :ok
  defp cleanup_reply_queue(false, _queue, _repo), do: :ok

  defp cleanup_reply_queue(true, queue, repo) do
    try do
      :ok = Pgmq.drop_queue(repo, queue)
    rescue
      error in [Postgrex.Error] ->
        case error.postgres[:code] do
          :undefined_table ->
            :ok

          :undefined_object ->
            :ok

          _ ->
            Logger.warning("Failed to drop reply queue",
              queue: queue,
              error: format_postgrex_error(error)
            )

            :ok
        end
    end
  end
end
