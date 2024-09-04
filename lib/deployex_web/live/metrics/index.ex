defmodule DeployexWeb.MetricsLive do
  use DeployexWeb, :live_view

  alias Deployex.Telemetry.Collector
  alias DeployexWeb.Components.Metrics.Table
  alias DeployexWeb.Components.MultiSearch

  @impl true
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_metrics_keys =
      assigns.node_info.metrics_keys -- assigns.node_info.selected_metrics_keys

    assigns =
      assigns
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_metrics_keys: unselected_metrics_keys)

    ~H"""
    <div class="min-h-screen bg-gray-500 ">
      <MultiSearch.content
        selected_text="Selected metrics"
        selected={[
          %{name: "service", keys: @node_info.selected_services_keys},
          %{name: "metric", keys: @node_info.selected_metrics_keys}
        ]}
        unselected={[
          %{name: "services", keys: @unselected_services_keys},
          %{name: "metrics", keys: @unselected_metrics_keys}
        ]}
        show_options={@show_metric_options}
      />

      <div class="p-2">
        <div class="grid grid-cols-3 w-3xl gap-2 items-center ">
          <%= for service <- @node_info.selected_services_keys do %>
            <%= for metric <- @node_info.selected_metrics_keys do %>
              <% app = Enum.find(@node_info.node, &(&1.service == service)) %>
              <%= if  metric in app.metrics_keys do %>
                <% data_key = data_key(service, metric) %>
                <Table.content
                  title={"#{metric} [#{app.name}]"}
                  service={service}
                  metric={metric}
                  transition={@metric_transient[data_key]["transition"]}
                  metrics={Map.get(@streams, data_key)}
                />
              <% end %>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    Collector.subscribe_for_new_keys()

    {:ok,
     socket
     |> assign(:node_info, update_node_info())
     |> assign(:node_data, %{})
     |> assign(:metric_transient, %{})
     |> assign(:show_metric_options, false)}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:node_data, %{})
     |> assign(:metric_transient, %{})
     |> assign(:show_metric_options, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "My Application Metrics")
  end

  @impl true
  def handle_event(
        "multi-select-remove-item",
        %{"item" => "service", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_metrics_keys
      )

    socket =
      Enum.reduce(node_info.selected_metrics_keys, socket, fn metric_key, acc ->
        Collector.unsubscribe_for_updates(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(data_key, [], reset: true)
        |> assign_metric_transient(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "metric", "key" => metric_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_metrics_keys -- [metric_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        Collector.unsubscribe_for_updates(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(data_key, [], reset: true)
        |> assign_metric_transient(data_key, %{"transition" => false})
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
        node_info.selected_metrics_keys
      )

    socket =
      Enum.reduce(node_info.selected_metrics_keys, socket, fn metric_key, acc ->
        Collector.subscribe_for_updates(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(
          data_key,
          Collector.list_by_service_key(service_key, metric_key),
          dom_id: &"#{data_key}-#{&1.timestamp}"
        )
        |> assign_metric_transient(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "metrics", "key" => metric_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_metrics_keys ++ [metric_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        Collector.subscribe_for_updates(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(
          data_key,
          Collector.list_by_service_key(service_key, metric_key),
          dom_id: &"#{data_key}-#{&1.timestamp}"
        )
        |> assign_metric_transient(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event("toggle-options", _value, socket) do
    show_metric_options = !socket.assigns.show_metric_options

    {:noreply, socket |> assign(:show_metric_options, show_metric_options)}
  end

  @impl true
  def handle_info({:metrics_new_data, service, key, data}, socket) do
    data_key = data_key(service, key)

    {:noreply,
     socket
     |> stream_insert(data_key, data, at: 0)
     |> assign_metric_transient(data_key, %{"transition" => true})}
  end

  def handle_info(
        {:metrics_new_keys, _service, _new_keys},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_metrics_keys
      )

    {:noreply,
     socket
     |> assign(:node_info, node_info)}
  end

  defp data_key(service, metric), do: "#{service}::#{metric}"

  defp assign_metric_transient(
         %{assigns: %{metric_transient: metric_transient}} = socket,
         data_key,
         attributes
       ) do
    updated_data =
      metric_transient
      |> Map.get(data_key, %{})
      |> Map.merge(attributes)

    assign(socket, :metric_transient, Map.put(metric_transient, data_key, updated_data))
  end

  defp node_info_new,
    do: %{
      services_keys: [],
      metrics_keys: [],
      selected_services_keys: [],
      selected_metrics_keys: [],
      node: []
    }

  defp update_node_info, do: update_node_info([], [])

  defp update_node_info(selected_services_keys, selected_metrics_keys) do
    initial_map = %{
      node_info_new()
      | selected_services_keys: selected_services_keys,
        selected_metrics_keys: selected_metrics_keys
    }

    Deployex.Storage.replicas_list()
    |> Enum.reduce(initial_map, fn instance,
                                   %{
                                     services_keys: services_keys,
                                     metrics_keys: metrics_keys,
                                     node: node
                                   } = acc ->
      instance_metrics_keys = Collector.get_keys_by_instance(instance)
      service = Collector.node_by_instance(instance) |> to_string
      [name, _hostname] = String.split(service, "@")

      metrics_keys = (metrics_keys ++ instance_metrics_keys) |> Enum.uniq()
      services_keys = services_keys ++ [service]

      node =
        if service in selected_services_keys do
          [
            %{
              name: name,
              metrics_keys: instance_metrics_keys,
              service: service
            }
            | node
          ]
        else
          node
        end

      %{acc | services_keys: services_keys, metrics_keys: metrics_keys, node: node}
    end)
  end
end
