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

    ~H"""
    <div class="min-h-screen bg-white">
      <div class="flex">
        <MultiSelect.content
          id="logs-live-multi-select"
          selected_text="Selected logs"
          selected={[
            %{name: "services", keys: @node_info.selected_services},
            %{name: "logs", keys: @node_info.selected_logs}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services},
            %{name: "logs", keys: @unselected_logs}
          ]}
          show_options={@show_log_options}
        />
        <button
          id="logs-live-multi-select-reset"
          phx-click="logs-live-reset"
          class="phx-submit-loading:opacity-75 rounded-lg bg-cyan-500 transform active:scale-75 transition-transform hover:bg-cyan-900 mb-1 py-2 px-3 mt-2 mr-2 text-sm font-semibold leading-6 text-white active:text-white/80"
        >
          RESET
        </button>
      </div>
      <div class="p-2">
        <div class="bg-white w-full shadow-lg rounded">
          <.table_logs id="logs-live-table" rows={@streams.log_messages}>
            <:col :let={{_id, log_message}} label="SERVICE">
              <div class="flex">
                <span
                  class="w-[5px] rounded ml-1 mr-1"
                  style={"background-color: #{log_message.color};"}
                >
                </span>
                <span>{log_message.service}</span>
              </div>
            </:col>
            <:col :let={{_id, log_message}} label="TYPE">
              {log_message.type}
            </:col>
            <:col :let={{_id, log_message}} label="CONTENT">
              {log_message.content}
            </:col>
          </.table_logs>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    {:ok,
     socket
     |> assign(:node_info, update_node_info())
     |> assign(:show_log_options, false)
     |> stream(:log_messages, [])}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:show_log_options, false)
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

  def handle_event("logs-live-reset", _value, socket) do
    {:noreply, stream(socket, :log_messages, [], reset: true)}
  end

  @impl true
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
      node: []
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

    (Monitor.list() ++ [Node.self()])
    |> Enum.reduce(initial_map, fn service_node,
                                   %{
                                     services_keys: services_keys,
                                     logs_keys: logs_keys,
                                     node: node
                                   } = acc ->
      service = to_string(service_node)
      services_keys = services_keys ++ [service]

      node_logs_keys = Logs.get_types_by_node(service_node)
      logs_keys = (logs_keys ++ node_logs_keys) |> Enum.uniq()

      node =
        if service in selected_services do
          [
            %{
              logs_keys: logs_keys,
              service: service
            }
            | node
          ]
        else
          node
        end

      %{acc | services_keys: services_keys, logs_keys: logs_keys, node: node}
    end)
  end
end
