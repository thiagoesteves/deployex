defmodule DeployexWeb.ApplicationsLive do
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

    <.modal
      :if={@live_action in [:logs_stdout, :logs_stderr]}
      id="app-log-modal"
      show
      on_cancel={JS.patch(~p"/applications")}
    >
      <.live_component
        module={DeployexWeb.ApplicationsLive.Logs}
        id={@selected_instance}
        title={@page_title}
        action={@live_action}
        process_stdout_log={@process_stdout_log}
        patch={~p"/applications"}
      />
    </.modal>

    <.terminal_modal
      :if={@live_action in [:terminal]}
      id="app-terminal-modal"
      show
      on_cancel={JS.patch(~p"/applications")}
    >
      <.live_component
        module={DeployexWeb.ApplicationsLive.Terminal}
        id={@selected_instance}
        title={@page_title}
        action={@live_action}
        process_stdout_log={@process_stdout_log}
        patch={~p"/applications"}
      />
    </.terminal_modal>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    Phoenix.PubSub.subscribe(Deployex.PubSub, AppStatus.listener_topic())

    state = :sys.get_state(AppStatus)

    socket
    |> assign(:monitoring_apps_data, state.monitoring)
    |> assign(:selected_instance, nil)
    |> assign(:process_stdout_log, nil)

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

  defp apply_action(socket, logs_type, %{"instance" => instance})
       when logs_type in [:logs_stdout, :logs_stderr] do
    socket
    |> assign(:page_title, "Application Logs")
    |> assign(:selected_instance, instance)
    |> assign(:process_stdout_log, nil)
  end

  defp apply_action(socket, :terminal, %{"instance" => instance}) do
    socket
    |> assign(:page_title, "Application Terminal")
    |> assign(:selected_instance, instance)
    |> assign(:process_stdout_log, nil)
  end

  @impl true
  def handle_info({:monitoring_app_updated, monitoring_apps_data}, socket) do
    {:noreply, assign(socket, :monitoring_apps_data, monitoring_apps_data)}
  end

  def handle_info({:stdout, _process, _message} = process_stdout_log, socket) do
    # NOTE: this stdout is coming from the erl_exec command
    # IO.inspect(message)
    {:noreply, assign(socket, :process_stdout_log, process_stdout_log)}
  end

  def handle_info({:cookie_updated}, socket) do
    {:noreply, assign(socket, :cookie_updated, nil)}
  end

  @impl true
  def handle_event("app-log-click", %{"instance" => instance, "std" => std}, socket) do
    {:noreply, push_patch(socket, to: std_ptah(instance, std))}
  end

  def handle_event("app-terminal-click", %{"instance" => instance}, socket) do
    {:noreply, push_patch(socket, to: ~p"/applications/#{instance}/terminal")}
  end

  defp std_ptah(instance, "stderr"), do: ~p"/applications/#{instance}/logs/stderr"
  defp std_ptah(instance, "stdout"), do: ~p"/applications/#{instance}/logs/stdout"
end
