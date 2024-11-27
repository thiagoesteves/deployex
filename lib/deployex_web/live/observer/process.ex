defmodule DeployexWeb.Observer.Process do
  @moduledoc false

  use DeployexWeb, :html
  use Phoenix.Component

  attr :process_info, :map, required: true

  def content(assigns) do
    process_info = assigns.process_info

    process_overview =
      if process_info do
        [
          %{name: "Id", value: "#{inspect(process_info.pid)}"},
          %{name: "Registered name", value: "#{process_info.registered_name}"},
          %{name: "Status", value: "#{process_info.meta.status}"},
          %{name: "Class", value: "#{process_info.meta.class}"},
          %{name: "Message Queue Length", value: "#{process_info.message_queue_len}"},
          %{name: "Group Leader", value: "#{inspect(process_info.relations.group_leader)}"},
          %{name: "Trap exit", value: "#{process_info.trap_exit}"}
        ]
      else
        nil
      end

    process_memory =
      if process_info do
        [
          %{name: "Total", value: "#{process_info.memory.total}"},
          %{name: "Heap Size", value: "#{process_info.memory.heap_size}"},
          %{name: "Stack Size", value: "#{process_info.memory.stack_size}"},
          %{name: "GC Min Heap Size", value: "#{process_info.memory.gc_min_heap_size}"},
          %{name: "GC FullSweep After", value: "#{process_info.memory.gc_full_sweep_after}"}
        ]
      else
        nil
      end

    assigns =
      assigns
      |> assign(process_overview: process_overview)
      |> assign(process_memory: process_memory)

    ~H"""
    <div class="max-w-full rounded overflow-hidden shadow-lg">
      <div :if={@process_info != nil} id="process_information">
        <div class="flex grid grid-cols-3  gap-1 items-top">
          <.table_process id="process-overview-table" title="Overview" rows={@process_overview}>
            <:col :let={item}>
              <span><%= item.name %></span>
            </:col>
            <:col :let={item}>
              <%= item.value %>
            </:col>
          </.table_process>

          <.table_process id="process-memory-table" title="Memory" rows={@process_memory}>
            <:col :let={item}>
              <span><%= item.name %></span>
            </:col>
            <:col :let={item}>
              <%= item.value %>
            </:col>
          </.table_process>

          <.relations title="State" value={"#{inspect(@process_info.state)}"} />
        </div>

        <div class="flex grid grid-cols-4 mt-1 gap-1 items-top">
          <.relations title="Links" value={"#{inspect(@process_info.relations.links)}"} />

          <.relations title="Ancestors" value={"#{inspect(@process_info.relations.ancestors)}" } />
          <.relations title="Monitors" value={"#{inspect(@process_info.relations.monitors)}"} />
          <.relations title="Monitored by" value={"#{inspect(@process_info.relations.monitored_by)}"} />
        </div>
      </div>
    </div>
    """
  end

  defp relations(assigns) do
    ~H"""
    <div class=" text-sm text-center block rounded-lg bg-white border border-solid border-blueGray-100 shadow-secondary-1 text-surface">
      <div class="font-mono font-semibold bg-gray-100  border-b-2 border-neutral-100 px-6 py-1">
        <%= @title %>
      </div>
      <div class="p-2">
        <span class="text-xs font-mono leading-tight">
          <%= @value %>
        </span>
      </div>
    </div>
    """
  end
end
