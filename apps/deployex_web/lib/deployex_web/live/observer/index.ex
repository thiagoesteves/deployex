defmodule DeployexWeb.ObserverLive do
  @moduledoc """
  """
  use DeployexWeb, :live_view

  alias DeployexWeb.Components.SystemBar

  @impl true
  def render(assigns) do
    ~H"""
    <SystemBar.content info={@host_info} />
    <div>
      <iframe
        src={~p"/observer/tracing?iframe=true"}
        class="min-h-screen"
        width="100%"
        height="100%"
        title="Observer Web"
      >
      </iframe>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    # Subscribe to receive System info
    Host.Memory.subscribe()

    {:ok, assign(socket, :host_info, nil)}
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :host_info, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Observer Web")
  end

  @impl true
  def handle_info({:update_system_info, host_info}, socket) do
    {:noreply, assign(socket, :host_info, host_info)}
  end
end
