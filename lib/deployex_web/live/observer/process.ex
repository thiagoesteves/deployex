defmodule DeployexWeb.Observer.Process do
  @moduledoc false

  use DeployexWeb, :html
  use Phoenix.Component

  alias DeployexWeb.Observer.Attention

  attr :info, :map, required: true
  attr :id, :map, required: true

  def content(assigns) do
    info = assigns.info

    {process_overview, process_memory} =
      if is_map(info) do
        process_overview =
          [
            %{name: "Id", value: "#{inspect(info.pid)}"},
            %{name: "Registered name", value: "#{info.registered_name}"},
            %{name: "Status", value: "#{info.meta.status}"},
            %{name: "Class", value: "#{info.meta.class}"},
            %{name: "Message Queue Length", value: "#{info.message_queue_len}"},
            %{name: "Group Leader", value: "#{inspect(info.relations.group_leader)}"},
            %{name: "Trap exit", value: "#{info.trap_exit}"}
          ]

        process_memory =
          [
            %{name: "Total", value: "#{info.memory.total}"},
            %{name: "Heap Size", value: "#{info.memory.heap_size}"},
            %{name: "Stack Size", value: "#{info.memory.stack_size}"},
            %{name: "GC Min Heap Size", value: "#{info.memory.gc_min_heap_size}"},
            %{name: "GC FullSweep After", value: "#{info.memory.gc_full_sweep_after}"}
          ]

        {process_overview, process_memory}
      else
        {nil, nil}
      end

    assigns =
      assigns
      |> assign(process_overview: process_overview)
      |> assign(process_memory: process_memory)

    ~H"""
    <div class="max-w-full rounded overflow-hidden shadow-lg">
      <%= cond do %>
        <% @info == nil -> %>
        <% @info == :undefined -> %>
          <Attention.content message={"Process #{@id} is either dead or protected and therefore can not be shown."} />
        <% true -> %>
          <div id="process_information">
            <div class="flex grid grid-cols-3  gap-1 items-top">
              <.table_process id="process-overview-table" title="Overview" rows={@process_overview}>
                <:col :let={item}>
                  <span>{item.name}</span>
                </:col>
                <:col :let={item}>
                  {item.value}
                </:col>
              </.table_process>

              <.table_process id="process-memory-table" title="Memory" rows={@process_memory}>
                <:col :let={item}>
                  <span>{item.name}</span>
                </:col>
                <:col :let={item}>
                  {item.value}
                </:col>
              </.table_process>
              <.relations title="State" value={"#{inspect(@info.state)}"} />
            </div>

            <div class="flex grid grid-cols-4 mt-1 gap-1 items-top">
              <.relations title="Links" value={"#{inspect(@info.relations.links)}"} />

              <.relations title="Ancestors" value={"#{inspect(@info.relations.ancestors)}" } />
              <.relations title="Monitors" value={"#{inspect(@info.relations.monitors)}"} />
              <.relations title="Monitored by" value={"#{inspect(@info.relations.monitored_by)}"} />
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  defp relations(assigns) do
    ~H"""
    <div class=" text-sm text-center block rounded-lg bg-white border border-solid border-blueGray-100 shadow-secondary-1 text-surface">
      <div class="font-mono font-semibold bg-gray-100  border-b-2 border-neutral-100 px-6 py-1">
        {@title}
      </div>
      <div class="p-2">
        <span class="text-xs font-mono leading-tight">
          {@value}
        </span>
      </div>
    </div>
    """
  end
end
