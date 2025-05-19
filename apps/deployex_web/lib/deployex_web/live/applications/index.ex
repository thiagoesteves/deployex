defmodule DeployexWeb.ApplicationsLive do
  use DeployexWeb, :live_view

  alias Deployer.Deployex
  alias Deployer.Monitor
  alias Deployer.Status
  alias DeployexWeb.ApplicationsLive.Logs
  alias DeployexWeb.ApplicationsLive.Terminal
  alias DeployexWeb.ApplicationsLive.Versions
  alias DeployexWeb.Components.Confirm
  alias DeployexWeb.Components.SystemBar
  alias Foundation.Common
  alias Host.Terminal.Server

  @manual_version_max_list 10
  @deployex_terminate_delay 300

  @impl true
  def render(assigns) do
    ~H"""
    <SystemBar.content info={@host_info} />

    <div class="min-h-screen bg-gray-700 ">
      <div class="p-5">
        <div class="grid grid-cols-3  gap-5 items-center p-30">
          <%= for app <- @monitoring_apps_data do %>
            <DeployexWeb.Components.AppCard.content
              supervisor={app.supervisor}
              status={app.status}
              node={app.node}
              sname={app.sname}
              crash_restart_count={app.crash_restart_count}
              force_restart_count={app.force_restart_count}
              name={app.name}
              version={app.version}
              uptime={app.uptime}
              otp={app.otp}
              tls={app.tls}
              last_deployment={app.last_deployment}
              last_ghosted_version={app.last_ghosted_version}
              restart_path={~p"/applications/#{app.sname}/restart"}
              mode={app.mode}
              manual_version={app.manual_version}
              versions={@versions}
              language={app.language}
            />
          <% end %>
        </div>
      </div>
    </div>

    <.modal
      :if={@live_action in [:logs_stdout, :logs_stderr]}
      id="app-log-modal"
      max_size="max-w-4xl"
      show
      on_cancel={JS.patch(~p"/applications")}
    >
      <.live_component
        module={Logs}
        id={@selected_sname}
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
        id={@selected_sname}
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
        id={@selected_sname}
        title={@page_title}
        terminal_process={@terminal_process}
        terminal_message={@terminal_message}
        cookie={Common.cookie()}
        patch={~p"/applications"}
      />
    </.terminal_modal>

    <%= if @live_action in [:restart] do %>
      <Confirm.content id={"app-restart-modal-#{@selected_sname}"}>
        <:header :if={@selected_sname == "deployex"}>
          <p class="text-red-500 text-center italic-text">Attention - All apps will be terminated</p>
        </:header>
        <:header :if={@selected_sname != "deployex"}>
          <p>Attention</p>
        </:header>
        <p :if={@selected_sname == "deployex"}>
          Are you sure you want to restart deployex?
        </p>
        <p :if={@selected_sname != "deployex"}>
          Are you sure you want to restart node {"#{@selected_sname}"}?
        </p>
        <:footer>
          <Confirm.cancel_button id={@selected_sname}>Cancel</Confirm.cancel_button>
          <Confirm.confirm_button event="restart" id={@selected_sname} value={@selected_sname}>
            Confirm
          </Confirm.confirm_button>
        </:footer>
      </Confirm.content>
    <% end %>

    <%= if @mode_confirmation.enabled do %>
      <Confirm.content id="app-set-mode-modal-deployex">
        <:header>Attention</:header>
        <p>
          Are you sure you want to set to {"#{@mode_confirmation.mode_or_version}"}?
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
    # Subscribe tor eceive Application Status
    Status.subscribe()

    # Subscribe to receive System info
    Host.Memory.subscribe()

    {:ok, monitoring} = Deployer.Status.monitoring()

    mode_or_version =
      monitoring
      |> Enum.find(&(&1.name == "deployex"))
      |> case do
        %{mode: :automatic} -> "automatic"
        app -> app.manual_version.version
      end

    socket =
      socket
      |> assign(:node, Node.self())
      |> assign(:host_info, nil)
      |> assign(:monitoring_apps_data, monitoring)
      |> assign(:selected_sname, nil)
      |> assign(:terminal_message, nil)
      |> assign(:terminal_process, nil)
      |> assign(:versions, [])
      |> assign(:mode_confirmation, %{
        enabled: false,
        mode_or_version: mode_or_version
      })

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node, Node.self())
     |> assign(:host_info, nil)
     |> assign(:monitoring_apps_data, [])
     |> assign(:selected_sname, nil)
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

  # NOTE: A terminal message was received without any configured terminal
  defp apply_action(%{assigns: %{terminal_message: terminal_message}} = socket, :index, _params) do
    Server.async_terminate(terminal_message.source_pid)

    socket
    |> assign(:page_title, "Listing Applications")
    |> assign(:terminal_message, nil)
    |> assign(:terminal_process, nil)
  end

  defp apply_action(socket, logs_type, %{"sname" => sname})
       when logs_type in [:logs_stdout, :logs_stderr] do
    socket
    |> assign(:page_title, "Application Logs")
    |> assign(:selected_sname, sname)
  end

  defp apply_action(socket, :terminal, %{"sname" => sname}) do
    socket
    |> assign(:page_title, "Application Terminal")
    |> assign(:selected_sname, sname)
  end

  defp apply_action(socket, :versions, %{"sname" => sname}) do
    socket
    |> assign(:page_title, "Monitored App version history")
    |> assign(:selected_sname, sname)
  end

  defp apply_action(socket, :restart, %{"sname" => sname}) do
    socket
    |> assign(:page_title, "Restart application")
    |> assign(:selected_sname, sname)
  end

  @impl true
  def handle_info({:update_system_info, host_info}, socket) do
    {:noreply, assign(socket, :host_info, host_info)}
  end

  def handle_info(
        {:monitoring_app_updated, source_node, monitoring_apps_data},
        %{assigns: %{node: node}} = socket
      )
      when source_node == node do
    {:noreply, assign(socket, :monitoring_apps_data, monitoring_apps_data)}
  end

  def handle_info({:monitoring_app_updated, _source_node, _monitoring_apps_data}, socket) do
    # NOTE: In future implementations, this will pattern match against other nodes
    #       to enable DeployEx to present its data.
    {:noreply, socket}
  end

  def handle_info({:terminal_update, %{metadata: metadata, status: :closed}}, socket)
      when metadata in [:iex_terminal, :logs_stdout, :logs_stderr] do
    {:noreply, push_patch(socket, to: ~p"/applications")}
  end

  def handle_info({:terminal_update, %{metadata: metadata, process: process} = msg}, socket)
      when metadata in [:iex_terminal, :logs_stdout, :logs_stderr] do
    # ATTENTION: This is the stdout from erl_exec command
    #            Be careful adding logs here, since it can create an infinity loop
    #            when using deployex web logs.
    {:noreply,
     socket
     |> assign(:terminal_message, msg)
     |> assign(:terminal_process, process)}
  end

  @impl true
  def handle_event("app-log-click", %{"sname" => sname, "std" => std}, socket) do
    {:noreply, push_patch(socket, to: std_path(sname, std))}
  end

  def handle_event("app-terminal-click", %{"sname" => sname}, socket) do
    {:noreply, push_patch(socket, to: ~p"/applications/#{sname}/terminal")}
  end

  def handle_event("app-versions-click", %{"sname" => sname}, socket) do
    {:noreply, push_patch(socket, to: ~p"/applications/#{sname}/versions")}
  end

  def handle_event("restart", %{"id" => "deployex"}, socket) do
    # NOTE: Say goodbye to your monitored applications
    Deployex.force_terminate(@deployex_terminate_delay)
    {:noreply, push_patch(socket, to: ~p"/applications")}
  end

  def handle_event("restart", %{"id" => sname}, socket) do
    Monitor.restart(sname)
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

  def handle_event(
        "app-mode-select",
        %{"select-mode" => rcv_mode_or_version},
        %{assigns: %{mode_confirmation: %{mode_or_version: mode_or_version}}} = socket
      )
      when rcv_mode_or_version == mode_or_version or mode_or_version == nil do
    {:noreply, push_patch(socket, to: ~p"/applications")}
  end

  def handle_event("app-mode-select", %{"select-mode" => mode_or_version}, socket) do
    {:noreply,
     socket
     |> assign(:mode_confirmation, %{enabled: true, mode_or_version: mode_or_version})
     |> push_patch(to: ~p"/applications")}
  end

  defp std_path(sname, "stderr"), do: ~p"/applications/#{sname}/logs/stderr"
  defp std_path(sname, "stdout"), do: ~p"/applications/#{sname}/logs/stdout"
end
