defmodule Foundation.Notifications.Recent.Server do
  @moduledoc """
  Keeps the last events that this host sent in a protected ETS table, and broadcasts each new one.
  """
  use GenServer

  alias Foundation.Notifications
  alias Foundation.Notifications.Recent

  @default_limit 100

  ### ==========================================================================
  ### GenServer callbacks
  ### ==========================================================================
  def start_link(args \\ []) do
    name = Keyword.get(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(args, :name, name), name: name)
  end

  @impl true
  def init(args) do
    name = Keyword.fetch!(args, :name)
    :ets.new(name, [:ordered_set, :protected, :named_table])
    :ok = Notifications.subscribe_events()

    {:ok, %{table: name, limit: Keyword.get(args, :limit, @default_limit), last_id: 0}}
  end

  @impl true
  def handle_info({event, payload}, %{table: table, limit: limit, last_id: last_id} = state)
      when is_binary(event) and is_map(payload) do
    # The id is the time in microseconds, so ids still grow after a restart and a browser's read mark holds
    id = max(last_id + 1, System.os_time(:microsecond))
    recent = %Recent{id: id, at: DateTime.utc_now(:second), event: event, payload: payload}
    :ets.insert(table, {id, recent})

    # The keys grow by one, so the first key is always the oldest event
    if :ets.info(table, :size) > limit, do: :ets.delete(table, :ets.first(table))

    Phoenix.PubSub.local_broadcast(
      Foundation.PubSub,
      Recent.topic(),
      {:recent_notification, recent}
    )

    {:noreply, %{state | last_id: id}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Returns the kept events, newest first. The list is empty when the server does not run.
  """
  @spec list(name :: atom()) :: [Recent.t()]
  def list(name \\ __MODULE__) do
    case :ets.whereis(name) do
      :undefined -> []
      table -> table |> :ets.tab2list() |> Enum.reverse() |> Enum.map(&elem(&1, 1))
    end
  end
end
