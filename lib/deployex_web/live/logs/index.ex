defmodule DeployexWeb.LogsLive do
  use DeployexWeb, :live_view

  alias Deployex.Status
  alias DeployexWeb.Components.MultiSearch

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
    <div class="min-h-screen bg-gray-500 ">
      <MultiSearch.content
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

      <div class="p-2">
        <div class="grid grid-cols-3 w-3xl gap-2 items-center ">
          <%= for service <- @node_info.selected_services_keys do %>
            <%= for log <- @node_info.selected_logs_keys do %>
              <% app = Enum.find(@node_info.node, &(&1.service == service)) %>
              <%!-- <%= if  metric in app.logs_keys do %>
                <% _data_key = data_key(service, metric) %>
              <% end %> --%>
            <% end %>
          <% end %>
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
     |> assign(:log_transient, %{})
     |> assign(:show_log_options, false)}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:node_data, %{})
     |> assign(:log_transient, %{})
     |> assign(:show_log_options, false)}
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
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_logs_keys
      )

    socket =
      Enum.reduce(node_info.selected_logs_keys, socket, fn log_key, acc ->
        # Collector.unsubscribe_for_updates(service_key, log_key)

        data_key = data_key(service_key, log_key)

        acc
        |> stream(data_key, [], reset: true)
        |> assign_log_transient(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
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

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        # Collector.unsubscribe_for_updates(service_key, log_key)

        data_key = data_key(service_key, log_key)

        acc
        |> stream(data_key, [], reset: true)
        |> assign_log_transient(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_logs_keys
      )

    socket =
      Enum.reduce(node_info.selected_logs_keys, socket, fn log_key, acc ->
        # Collector.subscribe_for_updates(service_key, log_key)

        data_key = data_key(service_key, log_key)

        acc
        # |> stream(
        #   data_key,
        #   Collector.list_by_service_key(service_key, log_key),
        #   dom_id: &"#{data_key}-#{&1.timestamp}"
        # )
        |> assign_log_transient(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "logs", "key" => log_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_logs_keys ++ [log_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        # Collector.subscribe_for_updates(service_key, log_key)

        data_key = data_key(service_key, log_key)

        acc
        # |> stream(
        #   data_key,
        #   Collector.list_by_service_key(service_key, log_key),
        #   dom_id: &"#{data_key}-#{&1.timestamp}"
        # )
        |> assign_log_transient(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event("toggle-options", _value, socket) do
    show_log_options = !socket.assigns.show_log_options

    {:noreply, socket |> assign(:show_log_options, show_log_options)}
  end

  @impl true
  def handle_info({:metrics_new_data, service, key, data}, socket) do
    data_key = data_key(service, key)

    {:noreply,
     socket
     |> stream_insert(data_key, data, at: 0)
     |> assign_log_transient(data_key, %{"transition" => true})}
  end

  def handle_info(
        {:metrics_new_keys, _service, _new_keys},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_logs_keys
      )

    {:noreply,
     socket
     |> assign(:node_info, node_info)}
  end

  defp data_key(service, log), do: "#{service}::#{log}"

  defp assign_log_transient(
         %{assigns: %{log_transient: log_transient}} = socket,
         data_key,
         attributes
       ) do
    updated_data =
      log_transient
      |> Map.get(data_key, %{})
      |> Map.merge(attributes)

    assign(socket, :log_transient, Map.put(log_transient, data_key, updated_data))
  end

  defp node_info_new do
    {:ok, hostname} = :inet.gethostname()
    app_name = Status.monitored_app_name()

    %{
      services_keys: [
        :"deployex@#{hostname}",
        :"#{app_name}-1@#{hostname}",
        :"#{app_name}-2@#{hostname}",
        :"#{app_name}-3@#{hostname}"
      ],
      logs_keys: [:stdout, :stderr],
      selected_services_keys: [],
      selected_logs_keys: [],
      node: []
    }
  end

  defp update_node_info, do: update_node_info([], [])

  defp update_node_info(selected_services_keys, selected_logs_keys) do
    %{
      node_info_new()
      | selected_services_keys: selected_services_keys,
        selected_logs_keys: selected_logs_keys
    }
  end
end
