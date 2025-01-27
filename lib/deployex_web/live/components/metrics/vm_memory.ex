defmodule DeployexWeb.Components.Metrics.VmMemory do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component

  attr :title, :string, required: true
  attr :service, :string, required: true
  attr :metric, :string, required: true
  attr :metrics, :list, required: true
  attr :cols, :integer, default: 2

  def content(assigns) do
    ~H"""
    <div :if={@metric == "vm.memory.total"} style={"grid-column: span #{@cols};"}>
      <% id = String.replace("#{@service}-vm-memory-total", "@", "-") %>
      <div class="relative flex flex-col min-w-0 break-words bg-white w-full shadow-lg rounded">
        <div class="rounded-t mb-0 px-4 py-3 border border-b border-solid">
          <div class="flex flex-wrap items-center">
            <div class="relative w-full px-4 max-w-full flex-grow flex-1">
              <h3 class="font-semibold text-base text-blueGray-700">
                {@title}
              </h3>
            </div>
          </div>
        </div>

        <% metrics = Enum.map(@metrics.inserts, fn {_id, _index, data, _} -> data end) %>
        <% normalized_metrics = normalize(metrics) %>
        <% echart_config = config(normalized_metrics) %>

        <div
          id={id}
          phx-hook="LiveMetricsEChart"
          data-config={Jason.encode!(echart_config)}
          data-reset={Jason.encode!(@metrics.reset?)}
          data-columns={Jason.encode!(@cols)}
          phx-update="ignore"
        >
          <div id={"#{id}-chart"} class="h-64" />
        </div>
      </div>
    </div>
    """
  end

  defp normalize(metrics) do
    empty_series_data = %{
      atom: [],
      atom_used: [],
      binary: [],
      code: [],
      ets: [],
      processes: [],
      processes_used: [],
      system: [],
      total: []
    }

    {series_data, categories_data} =
      Enum.reduce(metrics, {empty_series_data, []}, fn metric, {series_data, categories_data} ->
        timestamp =
          metric.timestamp
          |> trunc()
          |> DateTime.from_unix!(:millisecond)
          |> DateTime.to_string()

        {%{
           atom: series_data.atom ++ [metric.measurements.atom],
           atom_used: series_data.atom_used ++ [metric.measurements.atom_used],
           binary: series_data.binary ++ [metric.measurements.binary],
           code: series_data.code ++ [metric.measurements.code],
           ets: series_data.ets ++ [metric.measurements.ets],
           processes: series_data.processes ++ [metric.measurements.processes],
           processes_used: series_data.processes_used ++ [metric.measurements.processes_used],
           system: series_data.system ++ [metric.measurements.system],
           total: series_data.total ++ [metric.measurements.total]
         }, categories_data ++ [timestamp]}
      end)

    datasets =
      [
        %{
          name: "Atom",
          type: "line",
          data: series_data.atom
        },
        %{
          name: "Atom Used",
          type: "line",
          data: series_data.atom_used
        },
        %{
          name: "Binary",
          type: "line",
          data: series_data.binary
        },
        %{
          name: "Code",
          type: "line",
          data: series_data.code
        },
        %{
          name: "Ets",
          type: "line",
          data: series_data.ets
        },
        %{
          name: "Processes",
          type: "line",
          data: series_data.processes
        },
        %{
          name: "Processes Used",
          type: "line",
          data: series_data.processes_used
        },
        %{
          name: "System",
          type: "line",
          data: series_data.system
        },
        %{
          name: "Total",
          type: "line",
          data: series_data.total
        }
      ]

    %{
      datasets: datasets,
      categories: categories_data
    }
  end

  defp config(%{datasets: datasets, categories: categories}) do
    %{
      tooltip: %{
        trigger: "axis"
      },
      legend: %{
        data: [
          "Atom",
          "Atom Used",
          "Binary",
          "Code",
          "Ets",
          "Processes",
          "Processes Used",
          "System",
          "Total"
        ],
        right: "25%"
      },
      grid: %{
        left: "3%",
        right: "4%",
        bottom: "3%",
        top: "30%",
        containLabel: true
      },
      toolbox: %{
        feature: %{
          dataZoom: %{},
          dataView: %{},
          saveAsImage: %{}
        }
      },
      yAxis: %{
        type: "value",
        axisLabel: %{
          formatter: "{value} bytes"
        }
      },
      series: datasets,
      xAxis: %{
        type: "category",
        boundaryGap: false,
        data: categories
      }
    }
  end
end
