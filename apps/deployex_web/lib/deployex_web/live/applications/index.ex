defmodule DeployexWeb.ApplicationsLive do
  use DeployexWeb, :live_view

  alias Deployer.Deployex
  alias Deployer.Monitor
  alias Deployer.Status
  alias DeployexWeb.ApplicationsLive.Logs
  alias DeployexWeb.ApplicationsLive.Terminal
  alias DeployexWeb.ApplicationsLive.Versions
  alias DeployexWeb.Cache.UiSettings
  alias DeployexWeb.Components.Confirm
  alias DeployexWeb.Components.Dashboard
  alias DeployexWeb.Components.SystemBar
  alias Foundation.Common
  alias Host.Terminal.Server
  alias ObserverWeb.Telemetry

  @deployex_terminate_delay 300

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} ui_settings={@ui_settings} current_path={@current_path}>
      <div class="min-h-screen bg-base-300">
        <SystemBar.content info={@host_info} />
        <!-- Main Content -->
        <div class="p-3">
          <!-- Breadcrumb -->
          <div class="breadcrumbs text-sm mb-3">
            <ul>
              <li><a class="text-base-content/60">Home</a></li>
              <li class="text-base-content font-medium">Applications</li>
            </ul>
          </div>
          <Dashboard.content applications={@monitoring_apps_data} metrics={@metrics} />
        </div>
      </div>
    </Layouts.app>

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
          Critical Action - All Apps Will Be Terminated
        </:header>
        <:header :if={@selected_sname != "deployex"}>
          Restart Application
        </:header>

        <div :if={@selected_sname == "deployex"} class="space-y-6">
          <div class="bg-red-50 border border-red-200 rounded-2xl p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="w-8 h-8 bg-red-100 rounded-full flex items-center justify-center">
                <svg
                  class="w-5 h-5 text-red-600"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 9v2m0 4h.01"
                  >
                  </path>
                </svg>
              </div>
              <h4 class="font-bold text-red-800">Critical Warning</h4>
            </div>
            <p class="text-red-700 text-sm leading-relaxed">
              This will terminate all monitored applications and cannot be undone.
            </p>
          </div>
          <p class="text-base-content/90 leading-relaxed">
            Are you sure you want to restart <span class="font-semibold text-red-600">deployex</span>?
            All running applications will be affected.
          </p>
        </div>

        <div :if={@selected_sname != "deployex"} class="space-y-4">
          <p class="text-base-content/90 leading-relaxed">
            Are you sure you want to restart <span class="font-semibold text-primary">{"#{@selected_sname}"}</span>?
          </p>
          <div class="text-base-content/60 leading-relaxed">
            The application will be stopped and restarted automatically.
          </div>
        </div>

        <:footer>
          <Confirm.cancel_button id={@selected_sname}>Cancel</Confirm.cancel_button>
          <Confirm.danger_button
            :if={@selected_sname == "deployex"}
            event="restart"
            id={@selected_sname}
            value={@selected_sname}
          >
            Terminate All Apps
          </Confirm.danger_button>
          <Confirm.confirm_button
            :if={@selected_sname != "deployex"}
            event="restart"
            id={@selected_sname}
            value={@selected_sname}
          >
            Restart App
          </Confirm.confirm_button>
        </:footer>
      </Confirm.content>
    <% end %>

    <%= if @mode_confirmation do %>
      <Confirm.content id="app-set-mode-modal-deployex">
        <:header>Change Application Mode</:header>

        <div class="space-y-6">
          <div class="bg-blue-50 border border-blue-200 rounded-2xl p-6">
            <div class="flex items-center gap-3 mb-3">
              <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
                <svg
                  class="w-5 h-5 text-blue-600"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  >
                  </path>
                </svg>
              </div>
              <div>
                <h4 class="font-bold text-blue-800">Configuration Change</h4>
                <p class="text-blue-700 text-sm">
                  Application: <span class="font-semibold">{@mode_confirmation.name}</span>
                </p>
              </div>
            </div>
          </div>

          <p class="text-base-content/90 leading-relaxed">
            Change mode to <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-semibold bg-primary/10 text-primary">{"#{@mode_confirmation.mode_or_version}"}</span>?
          </p>

          <div class="text-base-content/60 leading-relaxed">
            This will update the application's deployment configuration.
          </div>
        </div>

        <:footer>
          <Confirm.cancel_button id="mode">Cancel</Confirm.cancel_button>
          <Confirm.confirm_button
            event="set-mode"
            id="mode"
            value={@mode_confirmation.mode_or_version}
          >
            Change Mode
          </Confirm.confirm_button>
        </:footer>
      </Confirm.content>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    # Subscribe to receive Application Status
    Status.subscribe()

    # Subscribe to receive System info
    Host.Memory.subscribe()

    {:ok, monitoring_apps_data} = Deployer.Status.monitoring()

    metrics = updated_metrics(monitoring_apps_data)

    socket =
      socket
      |> assign(:node, Node.self())
      |> assign(:host_info, nil)
      |> assign(:metrics, metrics)
      |> assign(:monitoring_apps_data, monitoring_apps_data)
      |> assign(:selected_name, nil)
      |> assign(:selected_sname, nil)
      |> assign(:terminal_message, nil)
      |> assign(:terminal_process, nil)
      |> assign(:mode_confirmation, nil)
      |> assign(:current_path, "/applications")

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node, Node.self())
     |> assign(:host_info, nil)
     |> assign(:metrics, %{})
     |> assign(:monitoring_apps_data, [])
     |> assign(:selected_name, nil)
     |> assign(:selected_sname, nil)
     |> assign(:terminal_message, nil)
     |> assign(:terminal_process, nil)
     |> assign(:mode_confirmation, nil)
     |> assign(:current_path, "/applications")}
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
  def handle_info(
        {:metrics_new_data, source_node, metric_key,
         %Telemetry.Data{measurements: %{total: count, limit: limit}}},
        %{assigns: %{metrics: metrics}} = socket
      ) do
    if source_node in metrics.monitored_nodes do
      current_percentage = trunc(count / limit * 100)

      [_vm, metric, _total] = String.split(metric_key, ".")
      metric = String.to_existing_atom(metric)

      new_node_metrics =
        metrics
        |> Map.get(source_node, %{})
        |> Map.put(metric, current_percentage)

      {:noreply, assign(socket, :metrics, Map.put(metrics, source_node, new_node_metrics))}
    else
      {:noreply, socket}
    end
  end

  # NOTE: Ignore any other metric value, like nil when the node is down
  def handle_info({:metrics_new_data, _source_node, _metric_key, _value}, socket) do
    {:noreply, socket}
  end

  def handle_info({:update_system_info, host_info}, %{assigns: %{metrics: metrics}} = socket) do
    # Sync ui_settings from cache to ensure NavMenu has latest state
    ui_settings = UiSettings.get()

    memory_used =
      trunc((host_info.memory_total - host_info.memory_free) / host_info.memory_total * 100)

    node = Node.self()

    new_node_metrics =
      metrics
      |> Map.get(node, %{})
      |> Map.put(:memory, memory_used)

    {:noreply,
     socket
     |> assign(:host_info, host_info)
     |> assign(:metrics, Map.put(metrics, node, new_node_metrics))
     |> assign(:ui_settings, ui_settings)}
  end

  def handle_info(
        {:monitoring_app_updated, source_node, monitoring_apps_data},
        %{assigns: %{node: node, metrics: metrics}} = socket
      )
      when source_node == node do
    # Sync ui_settings from cache to ensure NavMenu has latest state
    ui_settings = UiSettings.get()

    # Update monitored metrics and subscribe to receive metrics if needed
    metrics = updated_metrics(monitoring_apps_data, metrics)

    {:noreply,
     socket
     |> assign(:metrics, metrics)
     |> assign(:monitoring_apps_data, monitoring_apps_data)
     |> assign(:ui_settings, ui_settings)}
  end

  def handle_info({:monitoring_app_updated, _source_node, _monitoring_apps_data}, socket) do
    # NOTE: In future implementations, this will pattern match against other nodes
    #       to enable DeployEx to present its data.
    # Still sync ui_settings to ensure consistency
    ui_settings = UiSettings.get()
    {:noreply, assign(socket, :ui_settings, ui_settings)}
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
      application = Enum.find(socket.assigns.monitoring_apps_data, &(&1.name == name))

      current_mode_or_version =
        case application.config do
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

  defp updated_metrics(monitoring_apps_data, current \\ %{monitored_nodes: []}) do
    subscribe_app_if_new = fn %{node: node, monitoring: monitoring}, monitored_nodes ->
      if node not in current.monitored_nodes do
        monitoring
        |> Keyword.keys()
        |> Enum.each(&Telemetry.subscribe_for_new_data(node, "vm.#{&1}.total"))
      end

      monitored_nodes ++ [node]
    end

    new_monitored_nodes =
      Enum.reduce(monitoring_apps_data, [Node.self()], fn app, acc ->
        case app.children do
          [] ->
            acc

          children ->
            Enum.reduce(children, acc, &subscribe_app_if_new.(&1, &2))
        end
      end)

    %{current | monitored_nodes: new_monitored_nodes}
  end
end
