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
  PostgreSQL NOTIFY messaging infrastructure (NATS replacement).

  Provides complete real-time messaging capabilities for distributed systems.
  This enables instant message delivery without constant polling, replacing
  external messaging systems like NATS with PostgreSQL-native messaging.

  ## How it works

  1. **Send messages**: `send_with_notify/3` sends to pgmq + triggers NOTIFY
  2. **Listen for messages**: `listen/2` subscribes to PostgreSQL NOTIFY channels
  3. **Process messages**: Handle NOTIFY messages to trigger workflow processing

  ## Benefits

  - ✅ **Real-time**: Instant message delivery when events occur
  - ✅ **Efficient**: No constant polling, event-driven messaging
  - ✅ **Reliable**: Built on PostgreSQL's proven NOTIFY system
  - ✅ **Logged**: All messages are properly logged for debugging
  - ✅ **NATS replacement**: No external message brokers needed

  ## Example

      # Send message with NOTIFY
      {:ok, message_id} = Singularity.Workflow.Notifications.send_with_notify(
        "workflow_events",
        %{type: "task_completed", task_id: "123"},
        MyApp.Repo
      )

      # Listen for NOTIFY events
      {:ok, pid} = Singularity.Workflow.Notifications.listen("workflow_events", MyApp.Repo)

      # Handle notifications
      receive do
        {:notification, ^pid, channel, message_id} ->
          Logger.info("NOTIFY received on \#{channel} -> \#{message_id}")
          # Process the notification...
      end
  """

  @behaviour Singularity.Workflow.Notifications.Behaviour
  require Logger
  alias Pgmq
  alias Pgmq.Message

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
  def send_with_notify(queue_name, message, repo, opts \\ []) do
    start_time = System.monotonic_time()

    expect_reply? = Keyword.get(opts, :expect_reply, true)
    timeout_ms = Keyword.get(opts, :timeout, 30_000)
    poll_interval = Keyword.get(opts, :poll_interval, 100)

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

    with {:ok, message_id} <- send_pgmq_message(queue_name, enriched_message, repo),
         :ok <- trigger_notify(queue_name, message_id, repo),
         result <- maybe_wait_for_reply(expect_reply?, reply_queue, repo, timeout_ms, poll_interval) do
      duration = System.monotonic_time() - start_time

      Logger.info("PGMQ + NOTIFY sent successfully",
        queue: queue_name,
        message_id: message_id,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond),
        message_type:
          Map.get(enriched_message, :type, Map.get(enriched_message, "type", "unknown")),
        expect_reply: expect_reply?
      )

      cleanup_reply_queue(expect_reply?, reply_queue, repo)
      result
    else
      {:error, reason} ->
        Logger.error("PGMQ + NOTIFY send failed",
          queue: queue_name,
          error: inspect(reason),
          message_type:
            Map.get(enriched_message, :type, Map.get(enriched_message, "type", "unknown"))
        )

        cleanup_reply_queue(expect_reply?, reply_queue, repo)
        {:error, reason}
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
      msg_id_int =
        case Integer.parse(message_id) do
          {id, _} -> id
          :error -> raise ArgumentError, "Invalid message_id: #{message_id}"
        end

      # Delete the message from PGMQ
      :ok = Pgmq.delete_messages(repo, queue_name, [msg_id_int])

      Logger.debug("Message acknowledged",
        queue: queue_name,
        message_id: message_id
      )

      :ok
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
  defp send_pgmq_message(queue_name, message, repo) when is_binary(queue_name) do
    with {:ok, json} <- encode_message(message),
         {:ok, message_id} <- do_send(queue_name, json, repo) do
      {:ok, to_string(message_id)}
    end
  end

  defp encode_message(message) do
    case Jason.encode(message) do
      {:ok, json} ->
        {:ok, json}

      {:error, reason} ->
        Logger.error("Failed to encode pgmq message",
          error: inspect(reason),
          payload: inspect(message)
        )

        {:error, reason}
    end
  end

  defp do_send(queue_name, json_message, repo, attempts \\ 0)

  defp do_send(queue_name, json_message, repo, attempts) when attempts < 2 do
    try do
      case Pgmq.send_message(repo, queue_name, json_message) do
        {:ok, msg_id} ->
          {:ok, msg_id}

        {:error, reason} ->
          Logger.error("pgmq.send returned error",
            queue: queue_name,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      error in [Postgrex.Error] ->
        if queue_missing?(error) do
          case ensure_queue(queue_name, repo) do
            :ok -> do_send(queue_name, json_message, repo, attempts + 1)
            {:error, reason} -> {:error, reason}
          end
        else
          Logger.error("pgmq.send failed",
            queue: queue_name,
            error: format_postgrex_error(error)
          )

          {:error, error}
        end
    end
  end

  defp do_send(queue_name, _json_message, _repo, _attempts) do
    Logger.error("Failed to create pgmq queue after retry", queue: queue_name)
    {:error, :queue_create_failed}
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
  def ensure_queue(queue_name, repo) do
    try do
      :ok = Pgmq.create_queue(repo, queue_name)
    rescue
      error in [Postgrex.Error] ->
        case error.postgres[:code] do
          :duplicate_table ->
            :ok

          :duplicate_object ->
            :ok

          _ ->
            Logger.error("pgmq.create failed",
              queue: queue_name,
              error: format_postgrex_error(error)
            )

            {:error, error}
        end
    end
  end

  # Private: Trigger PostgreSQL NOTIFY after PGMQ send
  defp trigger_notify(queue_name, message_id, repo) do
    channel = "pgmq_#{queue_name}"

    case repo.query("SELECT pg_notify($1, $2)", [channel, message_id]) do
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
          message_id: message_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp queue_missing?(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: true

  defp queue_missing?(%Postgrex.Error{postgres: %{code: :undefined_object}}), do: true

  defp queue_missing?(%Postgrex.Error{postgres: %{message: message}}) when is_binary(message) do
    String.contains?(message, "does not exist")
  end

  defp queue_missing?(_), do: false

  defp format_postgrex_error(%Postgrex.Error{postgres: postgres} = _error) do
    %{code: postgres[:code], message: postgres[:message], detail: postgres[:detail]} |> inspect()
  end

  defp format_postgrex_error(error), do: inspect(error)

  defp ensure_reply_queue(false, _queue, _repo), do: :ok

  defp ensure_reply_queue(true, queue, repo) do
    ensure_queue(queue, repo)
  end

  defp maybe_wait_for_reply(false, _queue, _repo, _timeout, _poll_interval), do: :ok

  defp maybe_wait_for_reply(true, queue, repo, timeout_ms, poll_interval) do
    wait_for_reply(queue, repo, timeout_ms, poll_interval)
  end

  defp wait_for_reply(queue, repo, timeout_ms, poll_interval) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_reply(queue, repo, deadline, poll_interval)
  end

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

  defp decode_message_payload(msg) when is_binary(msg) do
    case Jason.decode(msg) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        Logger.error("Failed to decode reply message", error: inspect(reason), payload: msg)
        {:error, reason}
    end
  end

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
