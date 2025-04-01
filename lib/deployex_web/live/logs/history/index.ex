defmodule DeployexWeb.HistoryLive do
  use DeployexWeb, :live_view

  alias Deployex.Logs
  alias DeployexWeb.Components.Attention
  alias DeployexWeb.Components.MultiSelect
  alias DeployexWeb.Helper

  @impl true
  def render(assigns) do
    unselected_services =
      assigns.node_info.services_keys -- assigns.node_info.selected_services

    unselected_logs =
      assigns.node_info.logs_keys -- assigns.node_info.selected_logs

    attention_msg = ""

    assigns =
      assigns
      |> assign(unselected_services: unselected_services)
      |> assign(unselected_logs: unselected_logs)
      |> assign(attention_msg: attention_msg)

    ~H"""
    <div class="min-h-screen bg-white">
      <Attention.content
        id="logs-history-attention"
        title="Configuration"
        class="border-orange-400 text-orange-500 rounded-r-xl w-full"
        message={@attention_msg}
      >
        <:inner_form>
          <.form
            for={@form}
            id="logs-history-update-form"
            class="flex ml-2 mr-2 text-xs rounded-r-xl text-center text-black whitespace-nowrap gap-5"
            phx-change="form-update"
          >
            <.input
              field={@form[:start_time]}
              type="select"
              label="Start Time"
              options={["1m", "5m", "15m", "30m", "1h"]}
            />
          </.form>
        </:inner_form>
      </Attention.content>

      <div class="bg-white">
        <div class="flex">
          <MultiSelect.content
            id="logs-history-multi-select"
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
        </div>
        <div class="p-2">
          <div class="bg-white w-full shadow-lg rounded">
            <.table_logs id="logs-history-table" rows={@log_messages}>
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
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    {:ok,
     socket
     |> assign(:node_info, update_node_info())
     |> assign(form: to_form(default_form_options()))
     |> assign(:log_messages, [])
     |> assign(:show_log_options, false)}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
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
    |> assign(:page_title, "History Logs")
  end

  @impl true
  def handle_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services -- [service],
        node_info.selected_logs
      )

    start_time_integer = start_time_to_integer(form.params["start_time"])

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "logs", "key" => log},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services,
        node_info.selected_logs -- [log]
      )

    start_time_integer = start_time_to_integer(form.params["start_time"])

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services ++ [service],
        node_info.selected_logs
      )

    start_time_integer = start_time_to_integer(form.params["start_time"])

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "logs", "key" => log},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services,
        node_info.selected_logs ++ [log]
      )

    start_time_integer = start_time_to_integer(form.params["start_time"])

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:log_messages, log_messages)}
  end

  def handle_event("toggle-options", _value, socket) do
    show_log_options = !socket.assigns.show_log_options

    {:noreply, socket |> assign(:show_log_options, show_log_options)}
  end

  def handle_event(
        "form-update",
        %{"start_time" => start_time},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    start_time_integer = start_time_to_integer(start_time)

    log_messages = update_log_messages(node_info, start_time_integer)

    {:noreply,
     socket
     |> assign(form: to_form(%{"start_time" => start_time}))
     |> assign(:log_messages, log_messages)}
  end

  defp update_log_messages(node_info, start_time_integer) do
    Enum.reduce(node_info.selected_services, [], fn service, service_acc ->
      service_acc ++
        Enum.reduce(node_info.selected_logs, [], fn log, log_acc ->
          log_history = Logs.list_data_by_node_log_type(service, log, from: start_time_integer)

          log_acc ++ Helper.normalize_logs(log_history, service, log)
        end)
    end)
    |> Enum.sort(&(&1.timestamp <= &2.timestamp))
  end

  defp node_info_new do
    %{
      services_keys: [],
      logs_keys: ["stdout", "stderr"],
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

    Logs.list_active_nodes()
    |> Enum.reduce(initial_map, fn service,
                                   %{
                                     services_keys: services_keys,
                                     logs_keys: logs_keys,
                                     node: node
                                   } = acc ->
      service = to_string(service)
      services_keys = (services_keys ++ [service]) |> Enum.uniq()

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

  defp default_form_options, do: %{"num_cols" => "2", "start_time" => "5m"}

  defp start_time_to_integer("1m"), do: 1
  defp start_time_to_integer("5m"), do: 5
  defp start_time_to_integer("15m"), do: 15
  defp start_time_to_integer("30m"), do: 30
  defp start_time_to_integer("1h"), do: 60
end
