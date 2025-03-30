defmodule DeployexWeb.SlogsLive do
  use DeployexWeb, :live_view

  alias Deployex.Logs
  # alias Deployex.Terminal
  alias DeployexWeb.Components.MultiSelect
  alias DeployexWeb.Helper

  @impl true
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_logs_keys =
      assigns.node_info.logs_keys -- assigns.node_info.selected_logs_keys

    assigns =
      assigns
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_logs_keys: unselected_logs_keys)

    ~H"""
    <div class="min-h-screen bg-white">
      <div class="flex">
        <MultiSelect.content
          id="static-log-multi-select"
          selected_text="Selected logs"
          selected={[
            %{name: "services", keys: @node_info.selected_services_keys},
            %{name: "logs", keys: @node_info.selected_logs_keys}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services_keys},
            %{name: "logs", keys: @unselected_logs_keys}
          ]}
          show_options={@show_log_options}
        />
      </div>
      <div class="p-2">
        <div class="bg-white w-full shadow-lg rounded">
          <.table_logs id="static-live-logs" rows={@log_messages}>
            <:col :let={log_message} label="SERVICE">
              <div class="flex">
                <span
                  class="w-[5px] rounded ml-1 mr-1"
                  style={"background-color: #{log_message.color};"}
                >
                </span>
                <span>{log_message.service}</span>
              </div>
            </:col>
            <:col :let={log_message} label="TYPE">
              {log_message.type}
            </:col>
            <:col :let={log_message} label="CONTENT">
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
     |> assign(:node_data, %{})
     |> assign(form: to_form(default_form_options()))
     |> assign(:log_messages, [])
     |> assign(:show_log_options, false)}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:node_data, %{})
     |> assign(form: to_form(default_form_options()))
     |> assign(:log_messages, [])
     |> assign(:show_log_options, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Persisted Logs")
  end

  @impl true
  def handle_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_logs_keys
      )

    log_messages = update_log_messages(node_info)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "logs", "key" => log_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_logs_keys -- [log_key]
      )

    log_messages = update_log_messages(node_info)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_logs_keys
      )

    log_messages = update_log_messages(node_info)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "logs", "key" => log_key},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_logs_keys ++ [log_key]
      )

    log_messages = update_log_messages(node_info)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event("toggle-options", _value, socket) do
    show_log_options = !socket.assigns.show_log_options

    {:noreply, socket |> assign(:show_log_options, show_log_options)}
  end

  defp update_log_messages(node_info) do
    Enum.reduce(node_info.selected_services_keys, [], fn service_key, service_acc ->
      service_acc ++
        Enum.reduce(node_info.selected_logs_keys, [], fn log_key, log_key_acc ->
          data = Logs.list_data_by_node_log_type(service_key, log_key, [])

          log_key_acc ++ normalize_logs(data, service_key, log_key)
        end)
    end)
    |> Enum.sort(&(&1.timestamp <= &2.timestamp))
  end

  defp normalize_logs(data, service_key, log_key) do
    Enum.reduce(data, [], fn data, acc ->
      acc ++ normalize_log(data, service_key, log_key)
    end)
  end

  defp normalize_log(%{log: log, timestamp: timestamp}, service_key, log_key) do
    log
    |> String.split(["\n", "\r"], trim: true)
    |> Enum.map(fn content ->
      color = Helper.log_message_color(content, log_key)

      %{
        timestamp: timestamp,
        content: content,
        color: color,
        service: service_key,
        type: log_key
      }
    end)
  end

  defp node_info_new do
    %{
      services_keys: [],
      logs_keys: ["stdout", "stderr"],
      selected_services_keys: [],
      selected_logs_keys: [],
      node: []
    }
  end

  defp update_node_info, do: update_node_info([], [])

  defp update_node_info(selected_services_keys, selected_logs_keys) do
    initial_map =
      %{
        node_info_new()
        | selected_services_keys: selected_services_keys,
          selected_logs_keys: selected_logs_keys
      }

    Logs.list_active_nodes()
    |> Enum.reduce(initial_map, fn service,
                                   %{
                                     services_keys: services_keys,
                                     logs_keys: logs_keys,
                                     node: node
                                   } = acc ->
      service = to_string(service)
      services_keys = services_keys ++ [service]

      node =
        if service in selected_services_keys do
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

  defp default_form_options, do: %{"num_cols" => "2", "start_time" => "5m"}

  defp start_time_to_integer("1m"), do: 1
  defp start_time_to_integer("5m"), do: 5
  defp start_time_to_integer("15m"), do: 15
  defp start_time_to_integer("30m"), do: 30
  defp start_time_to_integer("1h"), do: 60
end
