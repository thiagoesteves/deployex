defmodule DeployexWeb.ObserverLive do
  use DeployexWeb, :live_view

  require Logger

  alias Deployex.Observer
  alias DeployexWeb.Components.MultiSelect
  alias DeployexWeb.Observer.Legend
  alias DeployexWeb.Observer.Process

  @tooltip_debouncing 50

  @impl true
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_apps_keys =
      assigns.node_info.apps_keys -- assigns.node_info.selected_apps_keys

    # credo:disable-for-lines:9
    adjust_series_position = fn series ->
      case Enum.count(series) do
        n when n > 0 ->
          step = 100.0 / n

          {series, _top, _bottom} =
            Enum.reduce(series, {[], 0.0, 100.0}, fn serie, {acc, top, bottom} ->
              bottom = bottom - step

              new_serie = %{
                serie
                | top: :erlang.float_to_binary(top, [{:decimals, 0}]) <> "%",
                  bottom: :erlang.float_to_binary(bottom, [{:decimals, 0}]) <> "%"
              }

              {acc ++ [new_serie], top + step, bottom}
            end)

          series

        _ ->
          series
      end
    end

    chart_tree_data =
      assigns.observer_data
      |> Enum.reduce([], fn {key, %{"data" => info}}, acc ->
        acc ++ [series(key, info)]
      end)
      |> adjust_series_position.()
      |> flare_chart_data()

    assigns =
      assigns
      |> assign(chart_tree_data: chart_tree_data)
      |> assign(unselected_services_keys: unselected_services_keys)
      |> assign(unselected_apps_keys: unselected_apps_keys)

    ~H"""
    <div class="min-h-screen bg-white ">
      <div class="flex">
        <MultiSelect.content
          id="observer-multi-select"
          selected_text="Selected apps"
          selected={[
            %{name: "services", keys: @node_info.selected_services_keys},
            %{name: "apps", keys: @node_info.selected_apps_keys}
          ]}
          unselected={[
            %{name: "services", keys: @unselected_services_keys},
            %{name: "apps", keys: @unselected_apps_keys}
          ]}
          show_options={@show_apps_options}
        />
        <button
          id="observer-multi-select-update"
          phx-click="observer-apps-update"
          class="phx-submit-loading:opacity-75 rounded-lg bg-cyan-500 transform active:scale-75 transition-transform hover:bg-cyan-900 mb-1 py-2 px-3 mt-2 mr-2 text-sm font-semibold leading-6 text-white active:text-white/80"
        >
          UPDATE
        </button>
      </div>
      <div class="p-2">
        <%= if @observer_data != %{}  do %>
          <Legend.content />
        <% end %>
        <div>
          <div id="tree" class="ml-5 mr-5 mt-10" phx-hook="EChart" data-merge={false}>
            <div id="tree-chart" style="width: 100%; height: 600px;" phx-update="ignore" />
            <div id="tree-data" hidden><%= Jason.encode!(@chart_tree_data) %></div>
          </div>
        </div>

        <Process.content process_info={@current_selected_process.info} />
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    # Adds notification is node is up or down
    :net_kernel.monitor_nodes(true)

    {:ok,
     socket
     |> assign(:node_info, update_node_info())
     |> assign(:node_data, %{})
     |> assign(:observer_data, %{})
     |> assign(:current_selected_process, %{info: nil, pid_string: nil, debouncing: 10})
     |> assign(:show_apps_options, false)}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:node_data, %{})
     |> assign(:observer_data, %{})
     |> assign(:current_selected_process, %{info: nil, pid_string: nil, debouncing: 10})
     |> assign(:show_apps_options, false)}
  end

  @impl true
  def handle_event("toggle-options", _value, socket) do
    show_apps_options = !socket.assigns.show_apps_options

    {:noreply, socket |> assign(:show_apps_options, show_apps_options)}
  end

  def handle_event(
        "request-process",
        value,
        %{assigns: %{current_selected_process: %{pid_string: pid_string, debouncing: debouncing}}} =
          socket
      )
      when pid_string != value or debouncing < 0 do
    pid? = String.contains?(value, "#PID<")

    current_selected_process =
      if pid? do
        pid =
          value
          |> String.trim_leading("#PID")
          |> String.to_charlist()
          |> :erlang.list_to_pid()

        Logger.info("Retrieving process info for pid: #{value}")

        %{info: Observer.Process.info(pid), pid_string: value, debouncing: @tooltip_debouncing}
      else
        reset_current_selected_process(value)
      end

    {:noreply, assign(socket, :current_selected_process, current_selected_process)}
  end

  # The debouncing added here will reduce the number of Process.info requests since
  # tooltips are high demand signals.
  def handle_event(
        "request-process",
        _value,
        %{assigns: %{current_selected_process: current_selected_process}} = socket
      ) do
    {:noreply,
     assign(socket, :current_selected_process, %{
       current_selected_process
       | debouncing: current_selected_process.debouncing - 1
     })}
  end

  def handle_event(
        "observer-apps-update",
        _value,
        %{assigns: %{observer_data: observer_data}} = socket
      ) do
    new_observer_data =
      Enum.reduce(observer_data, %{}, fn {key, data}, acc ->
        [service, app] = String.split(key, "::")

        new_info =
          Observer.info(String.to_existing_atom(service), String.to_existing_atom(app))

        Map.put(acc, key, %{data | "data" => new_info})
      end)

    {:noreply,
     socket
     |> assign(:observer_data, new_observer_data)}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_apps_keys
      )

    socket =
      Enum.reduce(node_info.selected_apps_keys, socket, fn app_key, acc ->
        data_key = data_key(service_key, app_key)

        update_observer_data(acc, data_key, nil)
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_process, reset_current_selected_process())}
  end

  def handle_event(
        "multi-select-remove-item",
        %{"item" => "apps", "key" => app_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_apps_keys -- [app_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        data_key = data_key(service_key, app_key)

        update_observer_data(acc, data_key, nil)
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_process, reset_current_selected_process())}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "services", "key" => service_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys ++ [service_key],
        node_info.selected_apps_keys
      )

    socket =
      Enum.reduce(node_info.selected_apps_keys, socket, fn app_key, acc ->
        node_service = Enum.find(node_info.node, &(&1.service == service_key))

        data_key = data_key(service_key, app_key)

        if app_key in node_service.apps_keys do
          info =
            Observer.info(String.to_existing_atom(service_key), String.to_existing_atom(app_key))

          update_observer_data(acc, data_key, %{"transition" => false, "data" => info})
        else
          update_observer_data(acc, data_key, nil)
        end
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_process, reset_current_selected_process())}
  end

  def handle_event(
        "multi-select-add-item",
        %{"item" => "apps", "key" => app_key},
        %{assigns: %{node_info: node_info}} = socket
      ) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_apps_keys ++ [app_key]
      )

    socket =
      Enum.reduce(node_info.selected_services_keys, socket, fn service_key, acc ->
        node_service = Enum.find(node_info.node, &(&1.service == service_key))

        data_key = data_key(service_key, app_key)

        if app_key in node_service.apps_keys do
          info =
            Observer.info(String.to_existing_atom(service_key), String.to_existing_atom(app_key))

          update_observer_data(acc, data_key, %{"transition" => false, "data" => info})
        else
          update_observer_data(acc, data_key, nil)
        end
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_process, reset_current_selected_process())}
  end

  @impl true
  def handle_info({:nodeup, _node}, %{assigns: %{node_info: node_info}} = socket) do
    node_info =
      update_node_info(
        node_info.selected_services_keys,
        node_info.selected_apps_keys
      )

    {:noreply, assign(socket, :node_info, node_info)}
  end

  def handle_info({:nodedown, node}, %{assigns: %{node_info: node_info}} = socket) do
    service_key = node |> to_string

    node_info =
      update_node_info(
        node_info.selected_services_keys -- [service_key],
        node_info.selected_apps_keys
      )

    socket =
      Enum.reduce(node_info.selected_apps_keys, socket, fn app_key, acc ->
        data_key = data_key(service_key, app_key)

        update_observer_data(acc, data_key, nil)
      end)

    {:noreply,
     socket
     |> assign(:node_info, node_info)
     |> assign(:current_selected_process, reset_current_selected_process())}
  end

  defp data_key(service, apps), do: "#{service}::#{apps}"

  defp update_observer_data(
         %{assigns: %{observer_data: observer_data}} = socket,
         data_key,
         nil
       ) do
    assign(socket, :observer_data, Map.delete(observer_data, data_key))
  end

  defp update_observer_data(
         %{assigns: %{observer_data: observer_data}} = socket,
         data_key,
         attributes
       ) do
    updated_data =
      observer_data
      |> Map.get(data_key, %{})
      |> Map.merge(attributes)

    assign(socket, :observer_data, Map.put(observer_data, data_key, updated_data))
  end

  defp node_info_new do
    %{
      services_keys: [],
      apps_keys: [],
      selected_services_keys: [],
      selected_apps_keys: [],
      node: []
    }
  end

  defp update_node_info, do: update_node_info([], [])

  defp update_node_info(selected_services_keys, selected_apps_keys) do
    initial_map =
      %{
        node_info_new()
        | selected_services_keys: selected_services_keys,
          selected_apps_keys: selected_apps_keys
      }

    Enum.reduce(Node.list() ++ [Node.self()], initial_map, fn instance_node,
                                                              %{
                                                                services_keys: services_keys,
                                                                apps_keys: apps_keys,
                                                                node: node
                                                              } = acc ->
      service = instance_node |> to_string
      [name, _hostname] = String.split(service, "@")
      services_keys = services_keys ++ [service]

      instance_app_keys = Observer.list(instance_node) |> Enum.map(&(&1.name |> to_string))
      apps_keys = (apps_keys ++ instance_app_keys) |> Enum.uniq()

      node =
        if service in selected_services_keys do
          [
            %{
              name: name,
              apps_keys: instance_app_keys,
              service: service
            }
            | node
          ]
        else
          node
        end

      %{acc | services_keys: services_keys, apps_keys: apps_keys, node: node}
    end)
  end

  defp reset_current_selected_process(pid_string \\ nil),
    do: %{info: nil, pid_string: pid_string, debouncing: @tooltip_debouncing}

  defp flare_chart_data(series) do
    %{
      tooltip: %{
        trigger: "item",
        triggerOn: "mousemove"
      },
      notMerge: true,
      legend: [
        %{
          top: "5%",
          left: "0%",
          orient: "vertical",
          borderColor: "#c23531"
        }
      ],
      series: series
    }
  end

  defp series(name, data) do
    %{
      type: "tree",
      name: name,
      data: [data],
      top: "0%",
      left: "30%",
      bottom: "74%",
      right: "20%",
      symbolSize: 10,
      itemStyle: %{color: "#93C5FD"},
      edgeShape: "curve",
      edgeForkPosition: "63%",
      initialTreeDepth: 3,
      lineStyle: %{
        width: 2
      },
      axisPointer: [
        %{
          show: "auto"
        }
      ],
      label: %{
        backgroundColor: "#fff",
        position: "top",
        verticalAlign: "middle",
        align: "center"
      },
      leaves: %{
        label: %{
          position: "right",
          verticalAlign: "middle",
          align: "left"
        }
      },
      emphasis: %{
        focus: "descendant"
      },
      roam: "zoom",
      symbol: "emptyCircle",
      expandAndCollapse: true,
      animationDuration: 550,
      animationDurationUpdate: 750
    }
  end
end
