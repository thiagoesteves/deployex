defmodule DeployexWeb.ObserverLive do
  use DeployexWeb, :live_view

  alias Deployex.Observer
  alias DeployexWeb.Components.MultiSelect

  @impl true
  def render(assigns) do
    unselected_services_keys =
      assigns.node_info.services_keys -- assigns.node_info.selected_services_keys

    unselected_apps_keys =
      assigns.node_info.apps_keys -- assigns.node_info.selected_apps_keys

    app_data =
      Observer.info()
      |> flare_chart_data()
      |> Jason.encode!()

    assigns =
      assigns
      |> assign(app_data: app_data)
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
          id="observer-multi-select-reset"
          phx-click="apps-reset"
          class="phx-submit-loading:opacity-75 rounded-lg bg-cyan-500 transform active:scale-75 transition-transform hover:bg-cyan-900 mb-1 py-2 px-3 mt-2 mr-2 text-sm font-semibold leading-6 text-white active:text-white/80"
        >
          UPDATE
        </button>
      </div>
      <div class="p-2">
        <div class="p-3 border border-black relative mt-5">
          <h2 class="absolute -top-1/2 translate-y-1/2 bg-white">Legend</h2>
          <div class="flex items-center">
            <span class="text-gray-600 dark:text-neutral-600">Process (App)</span>
            <div class="w-6 h-6 bg-white mr-3 flex items-center justify-center">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4 text-[#A1887F]"
              >
                <polygon points="12,2 22,12 12,22 2,12"></polygon>
              </svg>
            </div>

            <span class="text-gray-600 dark:text-neutral-600">Supervisor</span>
            <div class="w-6 h-6 rounded-lg bg-white mr-3 flex items-center justify-center">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4 text-[#F87171]"
              >
                <rect x="3" y="3" width="18" height="18" rx="4" ry="4"></rect>
              </svg>
            </div>

            <span class="text-gray-600 dark:text-neutral-600">Process (Worker)</span>
            <div class="w-6 h-6 rounded-full bg-white mr-3 flex items-center justify-center">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4 text-[#93C5FD]"
              >
                <circle cx="12" cy="12" r="8"></circle>
              </svg>
            </div>

            <span class="text-gray-600 dark:text-neutral-600">Port</span>
            <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4 text-[#FBBF24]"
              >
                <polygon points="12,2 22,22 2,22"></polygon>
              </svg>
            </div>

            <span class="text-gray-600 dark:text-neutral-600">Reference</span>
            <div class="w-6 h-6 rounded-lg bg-white mr-3 flex items-center justify-center">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4 text-[#28A745]"
              >
                <rect x="3" y="3" width="18" height="18"></rect>
              </svg>
            </div>

            <span class="text-gray-600 dark:text-neutral-600">Link</span>
            <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4"
              >
                <line x1="0" y1="12" x2="24" y2="12" stroke="#CCC" stroke-width="2"></line>
              </svg>
            </div>

            <span class="text-gray-600 dark:text-neutral-600">Monitor</span>
            <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4"
              >
                <line x1="0" y1="12" x2="24" y2="12" stroke="#D1A1E5" stroke-width="2"></line>
              </svg>
            </div>

            <span class="text-gray-600 dark:text-neutral-600">Monitored by</span>
            <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4"
              >
                <line x1="0" y1="12" x2="24" y2="12" stroke="#4DB8FF" stroke-width="2"></line>
              </svg>
            </div>
          </div>
        </div>

        <div>
          <div id="tree" class="ml-5 mr-5 mt-10" phx-hook="EChart">
            <div id="tree-chart" style="width: 80%; height: 600px;" phx-update="ignore" />
            <div id="tree-data" hidden><%= @app_data %></div>
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
     |> assign(:node_data, %{})
     |> assign(:current_config, %{})
     |> assign(:show_apps_options, false)}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:node_info, node_info_new())
     |> assign(:node_data, %{})
     |> assign(:current_config, %{})
     |> assign(:show_apps_options, false)}
  end

  @impl true
  def handle_event("toggle-options", _value, socket) do
    show_apps_options = !socket.assigns.show_apps_options

    {:noreply, socket |> assign(:show_apps_options, show_apps_options)}
  end

  def flare_chart_data(data) do
    %{
      tooltip: %{
        trigger: "item",
        triggerOn: "mousemove"
      },
      series: [
        %{
          type: "tree",
          id: 0,
          name: "tree1",
          data: [data],
          top: "5%",
          left: "5%",
          bottom: "5%",
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
      ]
    }
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

      node_app_keys = Observer.list(instance_node) |> Enum.map(&(&1.name |> to_string))
      apps_keys = (apps_keys ++ node_app_keys) |> Enum.uniq()

      node =
        if service in selected_services_keys do
          [
            %{
              name: name,
              apps_keys: apps_keys,
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
end
