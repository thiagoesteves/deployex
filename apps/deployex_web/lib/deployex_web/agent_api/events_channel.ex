defmodule DeployexWeb.AgentApi.EventsChannel do
  @moduledoc """
  Pushes every notification event of this host as an `event` message, with the
  body that the webhook adapter posts: `event`, `timestamp` and `payload`.
  """
  use DeployexWeb, :channel

  alias DeployexWeb.AgentApi.Tokens

  @impl true
  def join("events", _payload, socket) do
    if Tokens.allows?(socket.assigns.api_token, "read") do
      :ok = Foundation.Notifications.subscribe_events()
      {:ok, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
  def handle_info({event, payload}, socket) when is_binary(event) and is_map(payload) do
    push(socket, "event", %{
      event: event,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      payload: payload
    })

    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
