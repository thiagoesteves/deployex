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

  @deployex_terminate_delay 300

  @impl true
  def render(assigns) do
    ~H"""
    <SystemBar.content info={@host_info} />

    <div class="min-h-screen bg-gray-700 ">
      <div class="p-5">
        <div class="grid grid-cols-3 gap-5 items-start p-30">
          <%= for app <- @monitoring_apps_data do %>
            <DeployexWeb.Components.AppCard.content
              supervisor={app.supervisor}
              status={app.status}
              node={app.node}
              sname={app.sname}
              language={app.language}
              crash_restart_count={app.crash_restart_count}
              force_restart_count={app.force_restart_count}
              name={app.name}
              version={app.version}
              uptime={app.uptime}
              otp={app.otp}
              tls={app.tls}
              last_deployment={app.last_deployment}
              restart_path={~p"/applications/#{app.name}/#{app.sname}/restart"}
              metadata={app.metadata}
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
        id={"version-#{@selected_name}-#{@selected_sname}"}
        name={@selected_name}
        sname={@selected_sname}
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
          Are you sure you want to restart sname {"#{@selected_sname}"}?
        </p>
        <:footer>
          <Confirm.cancel_button id={@selected_sname}>Cancel</Confirm.cancel_button>
          <Confirm.confirm_button event="restart" id={@selected_sname} value={@selected_sname}>
            Confirm
          </Confirm.confirm_button>
        </:footer>
      </Confirm.content>
    <% end %>

    <%= if @mode_confirmation do %>
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

    socket =
      socket
      |> assign(:node, Node.self())
      |> assign(:host_info, nil)
      |> assign(:monitoring_apps_data, monitoring)
      |> assign(:selected_name, nil)
      |> assign(:selected_sname, nil)
      |> assign(:terminal_message, nil)
      |> assign(:terminal_process, nil)
      |> assign(:mode_confirmation, nil)

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node, Node.self())
     |> assign(:host_info, nil)
     |> assign(:monitoring_apps_data, [])
     |> assign(:selected_name, nil)
     |> assign(:selected_sname, nil)
     |> assign(:terminal_message, nil)
     |> assign(:terminal_process, nil)
     |> assign(:mode_confirmation, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(%{assigns: %{terminal_process: nil}} = socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Applications")
  end

  # NOTE: A terminal message was received without any configured terminal
  defp apply_action(%{assigns: %{terminal_message: terminal_message}} = socket, :index, _params) do
    Server.async_terminate(terminal_message.source_pid)

    socket
    |> assign(:page_title, "Listing Applications")
    |> assign(:terminal_message, nil)
    |> assign(:terminal_process, nil)
  end

  defp apply_action(socket, logs_type, %{"name" => name, "sname" => sname})
       when logs_type in [:logs_stdout, :logs_stderr] do
    socket
    |> assign(:page_title, "Application Logs")
    |> assign(:selected_name, name)
    |> assign(:selected_sname, sname)
  end

  defp apply_action(socket, :terminal, %{"name" => name, "sname" => sname}) do
    socket
    |> assign(:page_title, "Application Terminal")
    |> assign(:selected_name, name)
    |> assign(:selected_sname, sname)
  end

  defp apply_action(socket, :versions, %{"sname" => sname, "name" => name}) do
    socket
    |> assign(:page_title, "#{sname} version history")
    |> assign(:selected_name, name)
    |> assign(:selected_sname, sname)
  end

  defp apply_action(socket, :versions, %{"name" => name}) do
    socket
    |> assign(:page_title, "#{name} version history")
    |> assign(:selected_name, name)
    |> assign(:selected_sname, nil)
  end

  defp apply_action(socket, :restart, %{"name" => name, "sname" => sname}) do
    socket
    |> assign(:page_title, "Restart application")
    |> assign(:selected_name, name)
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
  def handle_event("app-log-click", %{"name" => name, "sname" => sname, "std" => std}, socket) do
    std_path = fn
      name, sname, "stderr" -> ~p"/applications/#{name}/#{sname}/logs/stderr"
      name, sname, "stdout" -> ~p"/applications/#{name}/#{sname}/logs/stdout"
    end

    {:noreply, push_patch(socket, to: std_path.(name, sname, std))}
  end

  def handle_event("app-terminal-click", %{"name" => name, "sname" => sname}, socket) do
    {:noreply, push_patch(socket, to: ~p"/applications/#{name}/#{sname}/terminal")}
  end

  def handle_event("app-versions-click", %{"name" => name, "sname" => sname}, socket) do
    {:noreply, push_patch(socket, to: ~p"/applications/#{name}/#{sname}/versions")}
  end

  def handle_event("app-versions-click", %{"name" => name}, socket) do
    {:noreply, push_patch(socket, to: ~p"/applications/#{name}/versions")}
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

  def handle_event("set-mode", %{"id" => _}, %{assigns: %{mode_confirmation: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event(
        "set-mode",
        %{"id" => mode_or_version},
        %{assigns: %{mode_confirmation: %{name: name}}} = socket
      ) do
    if mode_or_version == "automatic" do
      Status.set_mode(name, :automatic, "")
    else
      Status.set_mode(name, :manual, mode_or_version)
    end

    {:noreply,
     socket
     |> assign(:mode_confirmation, nil)
     |> push_patch(to: ~p"/applications")}
  end

  def handle_event("confirm-close-modal", _, socket) do
    {:noreply,
     socket
     |> assign(:mode_confirmation, nil)
     |> push_patch(to: ~p"/applications")}
  end

  def handle_event("app-mode-select", %{"select-mode" => mode_or_version, "name" => name}, socket) do
    # NOTE: this check is needed due to phoenix reconnect (replay form events)
    already_current? = fn name, mode_or_version ->
      metadata = Enum.find(socket.assigns.monitoring_apps_data, &(&1.name == "deployex")).metadata

      current_mode_or_version =
        case Map.get(metadata, name) do
          %{mode: :automatic} -> "automatic"
          %{manual_version: %{version: version}} -> version
        end

      current_mode_or_version == mode_or_version
    end

    if already_current?.(name, mode_or_version) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:mode_confirmation, %{name: name, mode_or_version: mode_or_version})
       |> push_patch(to: ~p"/applications")}
    end
  end
end
