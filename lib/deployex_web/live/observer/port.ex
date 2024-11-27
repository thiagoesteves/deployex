defmodule DeployexWeb.Observer.Port do
  @moduledoc false

  use DeployexWeb, :html
  use Phoenix.Component

  attr :info, :map, required: true

  def content(assigns) do
    info = assigns.info

    port_overview =
      if info do
        [
          %{name: "Id", value: "#{info.id}"},
          %{name: "Name", value: "#{info.name}"},
          %{name: "Os Pid", value: "#{info.os_pid}"},
          %{name: "Connected", value: "#{inspect(info.connected)}"}
        ]
      else
        nil
      end

    assigns =
      assigns
      |> assign(port_overview: port_overview)

    ~H"""
    <div class="max-w-full rounded overflow-hidden shadow-lg">
      <div :if={@info != nil} id="port_information">
        <div class="flex grid grid-cols-3  gap-1 items-top">
          <.table_process id="port-overview-table" title="Overview" rows={@port_overview}>
            <:col :let={item}>
              <span><%= item.name %></span>
            </:col>
            <:col :let={item}>
              <%= item.value %>
            </:col>
          </.table_process>
        </div>
      </div>
    </div>
    """
  end
end
