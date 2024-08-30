defmodule DeployexWeb.ApplicationsLive do
  use DeployexWeb, :live_view

  alias Deployex.Monitor
  alias Deployex.Status
  alias Deployex.Terminal.Server
  alias DeployexWeb.ApplicationsLive.Logs
  alias DeployexWeb.ApplicationsLive.Terminal
  alias DeployexWeb.ApplicationsLive.Versions
  alias DeployexWeb.Components.Confirm

  @manual_version_max_list 10

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-700 ">
      <div class="p-10">
        <div class="grid grid-cols-3  gap-10 items-center p-30">
          <%= for app <- @monitoring_apps_data do %>
            <DeployexWeb.Components.AppCard.content
              supervisor={app.supervisor}
              status={app.status}
              instance={app.instance}
              crash_restart_count={app.crash_restart_count}
              force_restart_count={app.force_restart_count}
              name={app.name}
              version={app.version}
              uptime={app.uptime}
              otp={app.otp}
              tls={app.tls}
              last_deployment={app.last_deployment}
              last_ghosted_version={app.last_ghosted_version}
              restart_path={~p"/applications/#{app.instance}/restart"}
              mode={app.mode}
              manual_version={app.manual_version}
              versions={@versions}
            />
          <% end %>
        </div>
      </div>
    </div>

    <.modal
      :if={@live_action in [:logs_stdout, :logs_stderr]}
      id="app-log-modal"
      show
      on_cancel={JS.patch(~p"/applications")}
    >
      <.live_component
        module={Logs}
        id={@selected_instance}
        title={@page_title}
        action={@live_action}
        terminal_process={@terminal_process}
        terminal_message={@terminal_message}
        patch={~p"/applications"}
      />
    </.modal>

    <.modal
      :if={@live_action in [:versions]}
      id="app-versions-modal"
      show
      on_cancel={JS.patch(~p"/applications")}
    >
      <.live_component
        module={Versions}
        id={@selected_instance}
        title={@page_title}
        action={@live_action}
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
        module={Terminal}
        id={@selected_instance}
        title={@page_title}
        action={@live_action}
        terminal_process={@terminal_process}
        terminal_message={@terminal_message}
        patch={~p"/applications"}
      />
    </.terminal_modal>

    <%= if @live_action in [:restart] do %>
      <Confirm.content id={"app-restart-modal-#{@selected_instance}"}>
        <:header>Attention</:header>
        <p>
          Are you sure you want to restart instance <%= "#{@selected_instance}" %>?
        </p>
        <:footer>
          <Confirm.cancel_button id={@selected_instance}>Cancel</Confirm.cancel_button>
          <Confirm.confirm_button event="restart" id={@selected_instance} value={@selected_instance}>
            Confirm
          </Confirm.confirm_button>
        </:footer>
      </Confirm.content>
    <% end %>

    <%= if @mode_confirmation.enabled do %>
      <Confirm.content id="app-set-mode-modal-0">
        <:header>Attention</:header>
        <p>
          Are you sure you want to set to <%= "#{@mode_confirmation.mode_or_version}" %>?
        </p>
        <:footer>
          <Confirm.cancel_button id="mode">
            Cancel
          </Confirm.cancel_button>
          <Confirm.confirm_button
            event="set-mode"
            id="mode"
            value={@mode_confirmation.mode_or_version}
          >
            Confirm
          </Confirm.confirm_button>
        </:footer>
      </Confirm.content>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    Phoenix.PubSub.subscribe(Deployex.PubSub, Status.listener_topic())

    {:ok, monitoring} = Deployex.Status.monitoring()

    socket =
      socket
      |> assign(:monitoring_apps_data, monitoring)
      |> assign(:selected_instance, nil)
      |> assign(:terminal_message, nil)
      |> assign(:terminal_process, nil)
      |> assign(:versions, [])
      |> assign(:mode_confirmation, %{
        enabled: false,
        mode_or_version: nil
      })

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:monitoring_apps_data, [])
     |> assign(:selected_instance, nil)
     |> assign(:terminal_message, nil)
     |> assign(:terminal_process, nil)
     |> assign(:versions, [])
     |> assign(:mode_confirmation, %{
       enabled: false,
       mode_or_version: nil
     })}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(%{assigns: %{terminal_process: nil}} = socket, :index, _params) do
    versions =
      Status.history_version_list()
      |> Enum.map(& &1.version)
      |> Enum.uniq()
      |> Enum.take(@manual_version_max_list)

    socket
    |> assign(:page_title, "Listing Applications")
    |> assign(:versions, versions)
  end

  defp apply_action(%{assigns: %{terminal_message: terminal_message}} = socket, :index, _params) do
    Server.async_terminate(terminal_message)

    socket
    |> assign(:page_title, "Listing Applications")
    |> assign(:terminal_message, nil)
    |> assign(:terminal_process, nil)
  end

  defp apply_action(socket, logs_type, %{"instance" => instance})
       when logs_type in [:logs_stdout, :logs_stderr] do
    socket
    |> assign(:page_title, "Application Logs")
    |> assign(:selected_instance, instance)
  end

  defp apply_action(socket, :terminal, %{"instance" => instance}) do
    socket
    |> assign(:page_title, "Application Terminal")
    |> assign(:selected_instance, instance)
  end

  defp apply_action(socket, :versions, %{"instance" => instance}) do
    socket
    |> assign(:page_title, "Monitored App version history")
    |> assign(:selected_instance, instance)
  end

  defp apply_action(socket, :restart, %{"instance" => instance}) do
    socket
    |> assign(:page_title, "Restart application")
    |> assign(:selected_instance, instance)
  end

  @impl true
  def handle_info({:monitoring_app_updated, monitoring_apps_data}, socket) do
    {:noreply, assign(socket, :monitoring_apps_data, monitoring_apps_data)}
  end

  def handle_info({:terminal_update, %{type: type, status: :closed}}, socket)
      when type in [:iex_terminal, :logs_stdout, :logs_stderr] do
    {:noreply, push_patch(socket, to: ~p"/applications")}
  end

  def handle_info({:terminal_update, %{type: type, process: process} = msg}, socket)
      when type in [:iex_terminal, :logs_stdout, :logs_stderr] do
    # ATTENTION: This is the stdout from erl_exec command
    #            Be careful adding logs here, since it can create an infinity loop
    #            when using deployex web logs.
    {:noreply,
     socket
     |> assign(:terminal_message, msg)
     |> assign(:terminal_process, process)}
  end

  @impl true
  def handle_event("app-log-click", %{"instance" => instance, "std" => std}, socket) do
    {:noreply, push_patch(socket, to: std_path(instance, std))}
  end

  def handle_event("app-terminal-click", %{"instance" => instance}, socket) do
    {:noreply, push_patch(socket, to: ~p"/applications/#{instance}/terminal")}
  end

  def handle_event("app-versions-click", %{"instance" => instance}, socket) do
    {:noreply, push_patch(socket, to: ~p"/applications/#{instance}/versions")}
  end

  def handle_event("restart", %{"id" => instance}, socket) do
    # Restart the application
    Monitor.restart(instance |> String.to_integer())
    {:noreply, push_patch(socket, to: ~p"/applications")}
  end

  def handle_event("set-mode", %{"id" => mode_or_version}, socket) do
    if mode_or_version == "automatic" do
      Status.set_mode(:automatic, "")
    else
      Status.set_mode(:manual, mode_or_version)
    end

    {:noreply,
     socket
     |> assign(:mode_confirmation, %{socket.assigns.mode_confirmation | enabled: false})
     |> push_patch(to: ~p"/applications")}
  end

  def handle_event("confirm-close-modal", _, socket) do
    {:noreply,
     socket
     |> assign(:mode_confirmation, %{socket.assigns.mode_confirmation | enabled: false})
     |> push_patch(to: ~p"/applications")}
  end

  def handle_event("app-mode-select", %{"select-mode" => mode_or_version}, socket) do
    {:noreply,
     socket
     |> assign(:mode_confirmation, %{enabled: true, mode_or_version: mode_or_version})
     |> push_patch(to: ~p"/applications")}
  end

  defp std_path(instance, "stderr"), do: ~p"/applications/#{instance}/logs/stderr"
  defp std_path(instance, "stdout"), do: ~p"/applications/#{instance}/logs/stdout"
end
