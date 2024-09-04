defmodule DeployexWeb.Components.Metrics.Table do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component

  attr :title, :string, required: true
  attr :service, :string, required: true
  attr :metric, :string, required: true
  attr :metrics, :list, required: true
  attr :span, :integer, default: 1
  attr :transition, :boolean, default: false

  attr :supported_metrics, :list,
    default: [
      "phoenix.router_dispatch.start.system_time",
      "phoenix.router_dispatch.stop.duration",
      "phoenix.endpoint.start.system_time",
      "phoenix.endpoint.stop.duration"
    ]

  def content(assigns) do
    ~H"""
    <div :if={@metric in @supported_metrics} class={"col-span-#{@span}"}>
      <div class="relative flex flex-col min-w-0 break-words bg-white w-full shadow-lg rounded h-64 overflow-y-auto">
        <div class="rounded-t mb-0 px-4 py-3 border-0">
          <div class="flex flex-wrap items-center">
            <div class="relative w-full px-4 max-w-full flex-grow flex-1">
              <h3 class="font-semibold text-base text-blueGray-700">
                <%= @title %>
              </h3>
            </div>
          </div>
        </div>

        <%= cond do %>
          <% @metric == "phoenix.router_dispatch.start.system_time" -> %>
            <div id={"#{@service}-#{@metric}"} class="block w-full overflow-x-auto">
              <.table_metrics
                id={"#{@service}-#{@metric}-table"}
                rows={@metrics}
                transition={@transition}
              >
                <:col :let={{_timestamp, metric}} label="Collected Time">
                  <.timestamp timestamp={metric.timestamp} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Start">
                  <.timestamp timestamp={metric.value} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Method">
                  <.method value={metric.tags.method} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Route"><%= metric.tags.route %></:col>
              </.table_metrics>
            </div>
          <% @metric == "phoenix.router_dispatch.stop.duration" -> %>
            <div id={"#{@service}-#{@metric}"} class="block w-full overflow-x-auto">
              <.table_metrics
                id={"#{@service}-#{@metric}-table"}
                rows={@metrics}
                transition={@transition}
              >
                <:col :let={{_timestamp, metric}} label="Collected Time">
                  <.timestamp timestamp={metric.timestamp} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Method">
                  <.method value={metric.tags.method} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Route"><%= metric.tags.route %></:col>
                <:col :let={{_timestamp, metric}} label="Duration">
                  <.duration value={metric.value} unit={metric.unit} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Status">
                  <.html_status status={metric.tags.status} />
                </:col>
              </.table_metrics>
            </div>
          <% @metric == "phoenix.endpoint.start.system_time" -> %>
            <div id={"#{@service}-#{@metric}"} class="block w-full overflow-x-auto">
              <.table_metrics
                id={"#{@service}-#{@metric}-table"}
                rows={@metrics}
                transition={@transition}
              >
                <:col :let={{_timestamp, metric}} label="Collected Time">
                  <.timestamp timestamp={metric.timestamp} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Start">
                  <.timestamp timestamp={metric.value} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Method">
                  <.method value={metric.tags.method} />
                </:col>
              </.table_metrics>
            </div>
          <% @metric == "phoenix.endpoint.stop.duration" -> %>
            <div id={"#{@service}-#{@metric}"} class="block w-full overflow-x-auto">
              <.table_metrics
                id={"#{@service}-#{@metric}-table"}
                rows={@metrics}
                transition={@transition}
              >
                <:col :let={{_timestamp, metric}} label="Collected Time">
                  <.timestamp timestamp={metric.timestamp} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Method">
                  <.method value={metric.tags.method} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Duration">
                  <.duration value={metric.value} unit={metric.unit} />
                </:col>
                <:col :let={{_timestamp, metric}} label="Status">
                  <.html_status status={metric.tags.status} />
                </:col>
              </.table_metrics>
            </div>
          <% true -> %>
        <% end %>
      </div>
    </div>
    """
  end

  defp timestamp(%{timestamp: timestamp} = assigns) when is_float(timestamp),
    do: timestamp(%{assigns | timestamp: trunc(timestamp)})

  defp timestamp(assigns) do
    ~H"""
    <div class="flex px-4 py-1 items-center rounded-full bg-gray-200">
      <span class="text-cyan-600 font-semibold text-[9px] ">
        <%= DateTime.from_unix!(@timestamp, :millisecond) %>
      </span>
    </div>
    """
  end

  defp method(assigns) do
    ~H"""
    <span class="text-black  font-semibold text-sm ">
      <%= @value %>
    </span>
    """
  end

  defp duration(%{unit: unit} = assigns) do
    unit =
      if unit == " millisecond" do
        "ms"
      else
        unit
      end

    assigns =
      assigns
      |> assign(unit: unit)

    ~H"""
    <span class="text-black  font-semibold text-sm ">
      <%= "#{:erlang.float_to_binary(@value, [{:decimals, 2}])} #{@unit}" %>
    </span>
    """
  end

  defp html_status(%{status: status} = assigns) do
    color =
      cond do
        status >= 200 and status < 300 ->
          "text-green-600"

        status >= 300 and status < 400 ->
          "text-yellow-600"

        status >= 400 and status < 600 ->
          "text-res-600"

        true ->
          "text-white"
      end

    assigns =
      assigns
      |> assign(color: color)

    ~H"""
    <div class="flex px-4 py-1 items-center rounded-full bg-gray-200">
      <span class={[@color, "font-semibold text-xs"]}>
        <%= @status %>
      </span>
    </div>
    """
  end
end
