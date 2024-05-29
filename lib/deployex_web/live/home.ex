defmodule DeployexWeb.HomeLive do
  use DeployexWeb, :live_view

  alias Deployex.AppStatus

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-700 ">
      <div class="p-10">
        <DeployexWeb.Components.AppCards.content monitoring_apps_data={@monitoring_apps_data} />
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    Phoenix.PubSub.subscribe(Deployex.PubSub, AppStatus.listener_topic())

    state = :sys.get_state(AppStatus)

    {:ok, assign(socket, :monitoring_apps_data, state.monitoring)}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :monitoring_apps_data, [])}
  end

  @impl true
  def handle_info({:monitoring_app_updated, monitoring_apps_data}, socket) do
    {:noreply, assign(socket, :monitoring_apps_data, monitoring_apps_data)}
  end
end
