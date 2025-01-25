defmodule DeployexWeb.MetricsLive do
  use DeployexWeb, :live_view

  alias Deployex.Telemetry
  alias DeployexWeb.Components.Metrics.Phoenix
  alias DeployexWeb.Components.Metrics.VmMemory
  alias DeployexWeb.Components.MultiSelect
  alias DeployexWeb.Components.SystemBar

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
    <SystemBar.content info={@host_info} />

    <div
      id="live-metrics-alert"
      class="p-2 mb-0.5 border-l-8 border-yellow-400 rounded-lg bg-gray-300 text-yellow-600"
      role="alert"
    >
      <div class="flex items-center">
        <div class="flex items-center py-8 mr-5">
          <svg
            class="flex-shrink-0 w-4 h-4 me-2"
            aria-hidden="true"
            xmlns="http://www.w3.org/2000/svg"
            fill="currentColor"
            viewBox="0 0 512 512"
          >
            <path d="M424.5,216.5h-15.2c-12.4,0-22.8-10.7-22.8-23.4c0-6.4,2.7-12.2,7.5-16.5l9.8-9.6c9.7-9.6,9.7-25.3,0-34.9l-22.3-22.1  c-4.4-4.4-10.9-7-17.5-7c-6.6,0-13,2.6-17.5,7l-9.4,9.4c-4.5,5-10.5,7.7-17,7.7c-12.8,0-23.5-10.4-23.5-22.7V89.1  c0-13.5-10.9-25.1-24.5-25.1h-30.4c-13.6,0-24.4,11.5-24.4,25.1v15.2c0,12.3-10.7,22.7-23.5,22.7c-6.4,0-12.3-2.7-16.6-7.4l-9.7-9.6  c-4.4-4.5-10.9-7-17.5-7s-13,2.6-17.5,7L110,132c-9.6,9.6-9.6,25.3,0,34.8l9.4,9.4c5,4.5,7.8,10.5,7.8,16.9  c0,12.8-10.4,23.4-22.8,23.4H89.2c-13.7,0-25.2,10.7-25.2,24.3V256v15.2c0,13.5,11.5,24.3,25.2,24.3h15.2  c12.4,0,22.8,10.7,22.8,23.4c0,6.4-2.8,12.4-7.8,16.9l-9.4,9.3c-9.6,9.6-9.6,25.3,0,34.8l22.3,22.2c4.4,4.5,10.9,7,17.5,7  c6.6,0,13-2.6,17.5-7l9.7-9.6c4.2-4.7,10.2-7.4,16.6-7.4c12.8,0,23.5,10.4,23.5,22.7v15.2c0,13.5,10.8,25.1,24.5,25.1h30.4  c13.6,0,24.4-11.5,24.4-25.1v-15.2c0-12.3,10.7-22.7,23.5-22.7c6.4,0,12.4,2.8,17,7.7l9.4,9.4c4.5,4.4,10.9,7,17.5,7  c6.6,0,13-2.6,17.5-7l22.3-22.2c9.6-9.6,9.6-25.3,0-34.9l-9.8-9.6c-4.8-4.3-7.5-10.2-7.5-16.5c0-12.8,10.4-23.4,22.8-23.4h15.2  c13.6,0,23.3-10.7,23.3-24.3V256v-15.2C447.8,227.2,438.1,216.5,424.5,216.5z M336.8,256L336.8,256c0,44.1-35.7,80-80,80  c-44.3,0-80-35.9-80-80l0,0l0,0c0-44.1,35.7-80,80-80C301.1,176,336.8,211.9,336.8,256L336.8,256z" />
          </svg>
          <span class="sr-only">Info</span>
          <h3 class="text-sm font-medium">Configuration</h3>
        </div>

        <.form
          for={@form}
          id="metrics-update-form"
          class="flex ml-2 mr-2 text-xs text-center text-black whitespace-nowrap gap-5"
          phx-change="form-update"
        >
          <.input
            field={@form[:num_cols]}
            type="select"
            label="Column Size"
            options={["1", "2", "3", "4"]}
          />
          <.input
            field={@form[:start_time]}
            type="select"
            label="Start Time"
            options={["1 minute", "5 minutes", "15 minutes", "30 minutes"]}
          />
        </.form>
      </div>
    </div>
    <div class="min-h-screen bg-gray-500 ">
      <MultiSelect.content
        id="metrics-multi-select"
        selected_text="Selected metrics"
        selected={[
          %{name: "services", keys: @node_info.selected_services_keys},
          %{name: "metrics", keys: @node_info.selected_metrics_keys}
        ]}
        unselected={[
          %{name: "services", keys: @unselected_services_keys},
          %{name: "metrics", keys: @unselected_metrics_keys}
        ]}
        show_options={@show_metric_options}
      />

      <div class="p-2">
        <div class="grid grid-cols-4 w-3xl gap-2 items-center ">
          <%= for service <- @node_info.selected_services_keys do %>
            <%= for metric <- @node_info.selected_metrics_keys do %>
              <% app = Enum.find(@node_info.node, &(&1.service == service)) %>
              <%= if  metric in app.metrics_keys do %>
                <% data_key = data_key(service, metric) %>
                <Phoenix.content
                  title={"#{metric} [#{app.name}]"}
                  service={service}
                  metric={metric}
                  cols={@form.params["num_cols"]}
                  transition={@metric_config[data_key]["transition"]}
                  metrics={Map.get(@streams, data_key)}
                />
                <VmMemory.content
                  title={"#{metric} [#{app.name}]"}
                  service={service}
                  metric={metric}
                  cols={@form.params["num_cols"]}
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
    # Subscribe to notifications if new metric is received
    Telemetry.subscribe_for_new_keys()

    # Subscribe to receive System info
    Deployex.System.subscribe()

    {:ok,
     socket
     |> assign(:node_info, update_node_info())
     |> assign(:node_data, %{})
     |> assign(:host_info, nil)
     |> assign(:metric_config, %{})
     |> assign(form: to_form(default_form_options()))
     |> assign(:show_metric_options, false)}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:node_data, %{})
     |> assign(:host_info, nil)
     |> assign(:metric_config, %{})
     |> assign(form: to_form(default_form_options()))
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
        "form-update",
        %{"num_cols" => num_cols, "start_time" => start_time},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    start_time_integer = start_time_to_integer(start_time)

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, service_acc ->
        Enum.reduce(node_info.selected_metrics_keys, service_acc, fn metric_key, metric_acc ->
          data_key = data_key(service_key, metric_key)

          metric_acc
          |> stream(data_key, [], reset: true)
          |> stream(
            data_key,
            Telemetry.list_data_by_node_key(service_key, metric_key, from: start_time_integer),
            dom_id: &"#{data_key}-#{&1.timestamp}"
          )
          |> assign_metric_config(data_key, %{"transition" => false})
        end)
      end)

    {:noreply,
     assign(socket, form: to_form(%{"num_cols" => num_cols, "start_time" => start_time}))}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_metrics_keys
      )

    socket =
      Enum.reduce(node_info.selected_metrics_keys, socket, fn metric_key, acc ->
        Telemetry.unsubscribe_for_new_data(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(data_key, [], reset: true)
        |> assign_metric_config(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "metrics", "key" => metric_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_metrics_keys -- [metric_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        Telemetry.unsubscribe_for_new_data(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(data_key, [], reset: true)
        |> assign_metric_config(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_metrics_keys
      )

    start_time = start_time_to_integer(form.params["start_time"])

    socket =
      Enum.reduce(node_info.selected_metrics_keys, socket, fn metric_key, acc ->
        Telemetry.subscribe_for_new_data(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(
          data_key,
          Telemetry.list_data_by_node_key(service_key, metric_key, from: start_time),
          dom_id: &"#{data_key}-#{&1.timestamp}"
        )
        |> assign_metric_config(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "metrics", "key" => metric_key},
        %{assigns: %{node_info: node_info, form: form}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_metrics_keys ++ [metric_key]
      )

    start_time = start_time_to_integer(form.params["start_time"])

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        Telemetry.subscribe_for_new_data(service_key, metric_key)

        data_key = data_key(service_key, metric_key)

        acc
        |> stream(
          data_key,
          Telemetry.list_data_by_node_key(service_key, metric_key, from: start_time),
          dom_id: &"#{data_key}-#{&1.timestamp}"
        )
        |> assign_metric_config(data_key, %{"transition" => false})
      end)

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_event("toggle-options", _value, socket) do
    show_metric_options = !socket.assigns.show_metric_options

    {:noreply, socket |> assign(:show_metric_options, show_metric_options)}
  end

  @impl true
  def handle_info({:update_system_info, host_info}, socket) do
    {:noreply, assign(socket, :host_info, host_info)}
  end

  def handle_info({:metrics_new_data, service, key, data}, socket) do
    data_key = data_key(service, key)

    {:noreply,
     socket
     |> stream_insert(data_key, data)
     |> assign_metric_config(data_key, %{"transition" => true})}
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

    {:noreply, assign(socket, :node_info, node_info)}
  end

  defp data_key(service, metric), do: "#{service}::#{metric}"

  defp assign_metric_config(
         %{assigns: %{metric_config: metric_config}} = socket,
         data_key,
         attributes
       ) do
    updated_data =
      metric_config
      |> Map.get(data_key, %{})
      |> Map.merge(attributes)

    assign(socket, :metric_config, Map.put(metric_config, data_key, updated_data))
  end

  defp default_form_options, do: %{"num_cols" => "2", "start_time" => "5 minutes"}

  defp start_time_to_integer("1 minute"), do: 1
  defp start_time_to_integer("5 minutes"), do: 5
  defp start_time_to_integer("15 minutes"), do: 15
  defp start_time_to_integer("30 minutes"), do: 30

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

    Deployex.Storage.instance_list()
    |> Enum.reduce(initial_map, fn instance,
                                   %{
                                     services_keys: services_keys,
                                     metrics_keys: metrics_keys,
                                     node: node
                                   } = acc ->
      instance_metrics_keys = Telemetry.get_keys_by_instance(instance)
      service = Telemetry.node_by_instance(instance) |> to_string
      [name, _hostname] = String.split(service, "@")

      metrics_keys = (metrics_keys ++ instance_metrics_keys) |> Enum.sort() |> Enum.uniq()
      services_keys = Enum.sort(services_keys ++ [service])

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
