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

    <.modal :if={@live_action in [:logs]} id="app-log-modal" show on_cancel={JS.patch(~p"/home")}>
      <.live_component
        module={DeployexWeb.HomeLive.LogComponent}
        id={@current_app}
        title={@page_title}
        action={@live_action}
        current_log={@current_log}
        patch={~p"/home"}
      />
    </.modal>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    Phoenix.PubSub.subscribe(Deployex.PubSub, AppStatus.listener_topic())

    state = :sys.get_state(AppStatus)

    socket
    |> assign(:monitoring_apps_data, state.monitoring)
    |> assign(:current_app, nil)
    |> assign(:current_log, nil)

    {:ok, assign(socket, :monitoring_apps_data, state.monitoring)}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :monitoring_apps_data, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Applications")
  end

  defp apply_action(socket, :logs, %{"instance" => instance}) do
    socket
    |> assign(:page_title, "Application Logs")
    |> assign(:current_app, instance)
    |> assign(:current_log, nil)
  end

  @impl true
  def handle_info({:monitoring_app_updated, monitoring_apps_data}, socket) do
    {:noreply, assign(socket, :monitoring_apps_data, monitoring_apps_data)}
  end

  def handle_info({:stdout, _process, _message} = current_log, socket) do
    {:noreply, assign(socket, :current_log, current_log)}
  end

  @impl true
  def handle_event("app-card-click", %{"instance" => instance, "std" => _std}, socket) do
    {:noreply, push_patch(socket, to: ~p"/home/#{instance}/logs")}
  end
end
