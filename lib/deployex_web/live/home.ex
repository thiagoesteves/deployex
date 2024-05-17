defmodule DeployexWeb.HomeLive do
  use DeployexWeb, :live_view

  alias Deployex.AppStatus

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-700 ">
      <div class="p-10">
        <DeployexWeb.Components.AppCards.content apps_data={@apps_data} />
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    Phoenix.PubSub.subscribe(Deployex.PubSub, AppStatus.listener_topic())

    {:ok, assign(socket, :apps_data, :sys.get_state(AppStatus))}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :apps_data, [])}
  end

  @impl true
  def handle_info({:update_apps_data, apps_data}, socket) do
    {:noreply, assign(socket, :apps_data, apps_data)}
  end
end
