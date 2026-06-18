defmodule Foundation.Notifications.Worker do
  @moduledoc """
  GenServer that backs a single notification channel.

  On startup the worker subscribes to one `Foundation.PubSub` topic per event
  in its `events` list (e.g. `"deployex::notifications::crash_restart"`).
  PubSub routing ensures only relevant messages arrive, so `handle_info/2`
  calls the adapter unconditionally — no filtering needed.

  Disabled workers (`enabled: false`) skip all subscriptions and therefore
  never receive any messages.

  Workers are started by `Foundation.Notifications.Supervisor`, one per entry
  in the `notifications:` YAML list.
  """

  use GenServer

  require Logger

  alias Foundation.Notifications
  alias Foundation.Yaml

  ### ==========================================================================
  ### GenServer callbacks
  ### ==========================================================================

  @spec start_link(Yaml.Notification.t()) :: GenServer.on_start()
  def start_link(%Yaml.Notification{} = config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(%Yaml.Notification{adapter: adapter, enabled: enabled, events: events} = config) do
    Logger.info("Initializing Notifications Worker for adapter: #{inspect(adapter)}")

    if enabled do
      Enum.each(events, fn event ->
        Phoenix.PubSub.subscribe(Foundation.PubSub, Notifications.topic(event))
      end)
    end

    {:ok, config}
  end

  @impl true
  def handle_info({event, payload}, config) do
    case config.adapter.notify(event, payload, config) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Notifications.Worker adapter=#{inspect(config.adapter)} event=#{event} reason=#{inspect(reason)}"
        )
    end

    {:noreply, config}
  end
end
