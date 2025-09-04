defmodule DeployexWeb.LogsLive do
  use DeployexWeb, :live_view

  alias Deployer.Monitor
  alias DeployexWeb.Components.MultiSelect
  alias DeployexWeb.Helper
  alias Sentinel.Logs

  @impl true
  def render(assigns) do
    unselected_services =
      assigns.node_info.services_keys -- assigns.node_info.selected_services

    unselected_logs =
      assigns.node_info.logs_keys -- assigns.node_info.selected_logs

    assigns =
      assigns
      |> assign(unselected_services: unselected_services)
      |> assign(unselected_logs: unselected_logs)
      |> assign(services_unselected_highlight: Monitor.list() ++ [Helper.self_sname()])

    ~H"""
    <Layouts.app flash={@flash} ui_settings={@ui_settings} current_path={@current_path}>
      <div class="min-h-screen bg-base-300">
        <!-- Header -->
        <div class="bg-base-100 border-b border-base-200 shadow-sm">
          <div class="max-w-7xl mx-auto px-6 py-6">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-3xl font-bold text-base-content">Live Logs</h1>
                <p class="text-base-content/60 mt-1">Real-time application logs monitoring</p>
              </div>
              <div class="flex items-center gap-4">
                <button
                  id="logs-live-multi-select-reset"
                  phx-click="logs-live-reset"
                  class="btn btn-error btn-sm"
                  phx-disable-with="Resetting..."
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                    >
                    </path>
                  </svg>
                  Reset
                </button>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Main Content -->
        <div class="max-w-7xl mx-auto px-6 py-6">
          <!-- Filters Card -->
          <div class="card bg-base-100 shadow-sm mb-6">
            <div class="card-body p-6">
              <h2 class="card-title text-lg mb-4">Log Filters</h2>
              <MultiSelect.content
                id="logs-live-multi-select"
                selected_text="Selected logs"
                selected={[
                  %{name: "services", keys: @node_info.selected_services},
                  %{name: "logs", keys: @node_info.selected_logs}
                ]}
                unselected={[
                  %{
                    name: "services",
                    keys: @unselected_services,
                    unselected_highlight: @services_unselected_highlight
                  },
                  %{name: "logs", keys: @unselected_logs, unselected_highlight: []}
                ]}
                show_options={@show_log_options}
              />
            </div>
          </div>
          
    <!-- Logs Display Card -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-0">
              <div class="overflow-x-auto">
                <.modern_logs_table id="logs-live-table" rows={@streams.log_messages} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    # Subscribe to receive a notification every time we have a new deploy
    Monitor.subscribe_new_deploy()

    {:ok,
     socket
     |> assign(:node_info, update_node_info())
     |> assign(:show_log_options, false)
     |> assign(:current_path, "/logs/live")
     |> stream(:log_messages, [])}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:show_log_options, false)
     |> assign(:current_path, "/logs/live")
     |> stream(:log_messages, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Live Logs")
  end

  @impl true
  def handle_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services -- [service],
        node_info.selected_logs
      )

    Enum.each(node_info.selected_logs, &Logs.unsubscribe_for_new_logs(service, &1))

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "logs", "key" => log},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services,
        node_info.selected_logs -- [log]
      )

    Enum.each(node_info.selected_services, &Logs.unsubscribe_for_new_logs(&1, log))

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services ++ [service],
        node_info.selected_logs
      )

    Enum.each(node_info.selected_logs, &Logs.subscribe_for_new_logs(service, &1))

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "logs", "key" => log},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services,
        node_info.selected_logs ++ [log]
      )

    Enum.each(node_info.selected_services, &Logs.subscribe_for_new_logs(&1, log))

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event("toggle-options", _value, socket) do
    show_log_options = !socket.assigns.show_log_options

    {:noreply, socket |> assign(:show_log_options, show_log_options)}
  end

  def handle_event(
        "logs-live-reset",
        _value,
        %{assigns: %{node_info: current_node_info}} = socket
      ) do
    # Unsubscribe from all current log subscriptions
    for service <- current_node_info.selected_services,
        log <- current_node_info.selected_logs do
      Logs.unsubscribe_for_new_logs(service, log)
    end

    # Reset log messages and filters
    node_info = update_node_info([], [])

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:show_log_options, false)
     |> stream(:log_messages, [], reset: true)
     |> put_flash(:info, "Logs and filters have been reset successfully")}
  end

  @impl true
  def handle_info(
        {:new_deploy, source_node, _sname},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    if source_node == Node.self() do
      node_info = update_node_info(node_info.selected_services, node_info.selected_logs)

      {:noreply, assign(socket, :node_info, node_info)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:logs_new_data, service, log_type, data}, socket) do
    messages = Helper.normalize_log(data, service, log_type)

    {:noreply, stream(socket, :log_messages, messages)}
  end

  defp node_info_new do
    %{
      services_keys: [],
      logs_keys: [],
      selected_services: [],
      selected_logs: [],
      sname: []
    }
  end

  defp update_node_info, do: update_node_info([], [])

  defp update_node_info(selected_services, selected_logs) do
    initial_map =
      %{
        node_info_new()
        | selected_services: selected_services,
          selected_logs: selected_logs
      }

    (Monitor.list() ++ [Helper.self_sname()])
    |> Enum.reduce(initial_map, fn service_sname,
                                   %{
                                     services_keys: services_keys,
                                     logs_keys: logs_keys,
                                     sname: sname
                                   } = acc ->
      service = to_string(service_sname)
      services_keys = services_keys ++ [service]

      sname_logs_keys = Logs.get_types_by_sname(service_sname)
      logs_keys = (logs_keys ++ sname_logs_keys) |> Enum.uniq()

      sname =
        if service in selected_services do
          [
            %{
              logs_keys: logs_keys,
              service: service
            }
            | sname
          ]
        else
          sname
        end

      %{acc | services_keys: services_keys, logs_keys: logs_keys, sname: sname}
    end)
  end
end
