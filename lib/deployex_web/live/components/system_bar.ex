defmodule DeployexWeb.Components.SystemBar do
  @moduledoc """
  Memory Bar
  """
  use Phoenix.Component

  attr :info, :map, required: true

  @one_gigabyte 1_073_741_824

  def content(assigns) do
    info = assigns.info

    assigns =
      if is_nil(info) or is_nil(info.memory_free) or is_nil(info.cpu) do
        assigns
        |> assign(system: "--")
        |> assign(description: "--")
        |> assign(memory_used: 0)
        |> assign(memory_max: "--")
        |> assign(cpu: 0)
        |> assign(cpus_used: 0)
        |> assign(cpus_max: "--")
      else
        memory_used = trunc((info.memory_total - info.memory_free) / info.memory_total * 100)
        memory_max = :erlang.float_to_binary(info.memory_total / @one_gigabyte, [{:decimals, 2}])

        cpus_max = trunc(info.cpus * 100)
        cpus_used = trunc(info.cpu / cpus_max * 100)

        assigns
        |> assign(system: info.host)
        |> assign(description: info.description)
        |> assign(memory_used: memory_used)
        |> assign(memory_max: memory_max)
        |> assign(cpu: info.cpu)
        |> assign(cpus_used: cpus_used)
        |> assign(cpus_max: cpus_max)
      end

    ~H"""
    <div class="items-center">
      <div
        id="live-memory-bar"
        class="flex p-1 border-l-8 border-blue-400 rounded bg-gray-300 text-blue-500"
        role="alert"
      >
        <div class="flex items-center py-2">
          <svg
            class="flex-shrink-0 w-4 h-4 me-2"
            aria-hidden="true"
            xmlns="http://www.w3.org/2000/svg"
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path d="M3 4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V4zm2 0v10h10V4H5zm1 12h8v2H6v-2z" />
          </svg>
          <span class="sr-only">Info</span>
          <h3 class="text-sm font-medium text-nowrap ">{@system} - {@description}</h3>
        </div>

        <div class="grid grid-cols-6  w-full items-center">
          <div class="text-center text-black text-xs font-bold">MEMORY</div>

          <div>
            <div class="rounded-full border border-blue-500 p-1 bg-gradient-to-tr from-indigo-600 to-green-600 p-0.5">
              <div
                class="flex h-6 items-center justify-center rounded-full bg-blue-300 text-xs leading-none"
                style={["width: #{@memory_used}%;", "height: 85%;"]}
              >
                <span class="p-1 text-black font-bold text-nowrap">{@memory_used}%</span>
              </div>
            </div>
          </div>

          <div class="ml-3 text-xs text-black font-bold">{@memory_max}G</div>

          <div class="text-center text-black text-xs  font-bold">CPU</div>

          <div>
            <div class="rounded-full border border-blue-500 p-1 bg-gradient-to-tr from-indigo-600 to-green-600 p-0.5">
              <div
                class="flex h-6 items-center justify-center rounded-full bg-blue-300 text-xs leading-none"
                style={["width: #{@cpus_used}%;", "height: 85%;"]}
              >
                <span class="p-1 text-black font-bold text-nowrap">{@cpu} %</span>
              </div>
            </div>
          </div>

          <div class="ml-3 text-xs text-black font-bold">{@cpus_max}%</div>
        </div>
      </div>
    </div>
    """
  end
end
