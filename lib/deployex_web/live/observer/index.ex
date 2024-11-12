defmodule DeployexWeb.ObserverLive do
  use DeployexWeb, :live_view

  alias Deployex.Observer

  @impl true
  def render(assigns) do
    app_data =
      Observer.info()
      |> flare_chart_data()
      |> Jason.encode!()

    assigns =
      assigns
      |> assign(app_data: app_data)

    ~H"""
    <div class="p-3 border border-black relative mt-5">
      <h2 class="absolute -top-1/2 translate-y-1/2 bg-white">Legend</h2>
      <!-- Process -->
      <div class="flex items-center">
        <span class="text-gray-600 dark:text-neutral-400">Process (App)</span>
        <div class="w-6 h-6 bg-white mr-3 flex items-center justify-center">
          <!-- Empty Diamond -->
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

        <span class="text-gray-600 dark:text-neutral-400">Supervisor</span>
        <div class="w-6 h-6 rounded-lg bg-white mr-3 flex items-center justify-center">
          <!-- Empty Round Rectangle -->
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

        <span class="text-gray-600 dark:text-neutral-400">Process (Worker)</span>
        <div class="w-6 h-6 rounded-full bg-white mr-3 flex items-center justify-center">
          <!-- Empty Circle -->
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

        <span class="text-gray-600 dark:text-neutral-400">Port</span>
        <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
          <!-- Empty Triangle -->
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

        <span class="text-gray-600 dark:text-neutral-400">Link</span>
        <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
          <!-- Empty Triangle -->
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

        <span class="text-gray-600 dark:text-neutral-400">Monitor</span>
        <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
          <!-- Empty Triangle -->
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

        <span class="text-gray-600 dark:text-neutral-400">Monitored by</span>
        <div class="w-6 h-6 bg-white mr-2 flex items-center justify-center">
          <!-- Empty Triangle -->
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
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
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
end
