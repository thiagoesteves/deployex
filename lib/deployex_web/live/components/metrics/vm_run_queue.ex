defmodule DeployexWeb.Components.Metrics.VmRunQueue do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component

  attr :title, :string, required: true
  attr :service, :string, required: true
  attr :metric, :string, required: true
  attr :metrics, :list, required: true
  attr :cols, :integer, default: 2

  attr :supported_metrics, :list,
    default: [
      "vm.total_run_queue_lengths.total",
      "vm.total_run_queue_lengths.cpu",
      "vm.total_run_queue_lengths.io"
    ]

  def content(assigns) do
    ~H"""
    <div :if={@metric in @supported_metrics} style={"grid-column: span #{@cols};"}>
      <% id = String.replace("#{@service}-#{@metric}", ["@", ".", "/"], "-") %>
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
    {series_data, categories_data} =
      Enum.reduce(metrics, {[], []}, fn metric, {series_data, categories_data} ->
        timestamp =
          metric.timestamp
          |> trunc()
          |> DateTime.from_unix!(:millisecond)
          |> DateTime.to_string()

        {series_data ++ [metric.value], categories_data ++ [timestamp]}
      end)

    datasets =
      [
        %{
          name: "Value",
          type: "line",
          data: series_data
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
          formatter: "{value}"
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
