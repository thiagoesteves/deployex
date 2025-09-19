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
        |> assign(cpu: 0.00)
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
    <div class="bg-base-100 shadow-sm">
      <div id="live-memory-bar" class="navbar h-16 px-8" role="banner">
        <div class="navbar-start">
          <div class="flex items-center gap-8">
            <!-- Tech Stack -->
            <div class="flex items-center gap-6">
              <div class="flex items-center gap-3">
                <img src="/images/erlang-otp.png" alt="OTP" class="w-8 h-8" />
                <div class="flex flex-col">
                  <span class="text-sm font-semibold text-base-content">OTP</span>
                  <span class="text-xs text-base-content/60">{System.otp_release()}</span>
                </div>
              </div>

              <div class="flex items-center gap-3">
                <img src="/images/elixir.png" alt="Elixir" class="w-8 h-8" />
                <div class="flex flex-col">
                  <span class="text-sm font-semibold text-base-content">Elixir</span>
                  <span class="text-xs text-base-content/60">v{Application.spec(:elixir, :vsn)}</span>
                </div>
              </div>

              <div class="flex items-center gap-3">
                <img src="/images/phoenix.png" alt="Phoenix" class="w-8 h-8" />
                <div class="flex flex-col">
                  <span class="text-sm font-semibold text-base-content">Phoenix</span>
                  <span class="text-xs text-base-content/60">
                    v{Application.spec(:phoenix, :vsn)}
                  </span>
                </div>
              </div>
            </div>
            
    <!-- System Info -->
            <div class="divider divider-horizontal mx-4"></div>
            <div class="flex items-center gap-3">
              <img src={"/images/#{host_system_image(@system)}"} alt="System" class="w-8 h-8" />
              <div class="flex flex-col">
                <span class="text-sm font-semibold text-base-content">{@system}</span>
                <span class="text-xs text-base-content/60">{@description}</span>
              </div>
            </div>
          </div>
        </div>

        <div class="navbar-end">
          <div class="flex items-center gap-8">
            <!-- Memory Usage -->
            <div class="flex items-center gap-3">
              <div class="flex flex-col items-end">
                <span class="text-sm font-semibold text-base-content">Memory</span>
                <span class="text-xs text-base-content/60">{@memory_max}G Total</span>
              </div>
              <div class="flex items-center gap-2">
                <progress class="progress progress-info w-20 h-2" value={@memory_used} max="100">
                </progress>
                <span class="text-sm font-bold text-info min-w-[3rem] text-right">
                  {@memory_used}%
                </span>
              </div>
            </div>
            
    <!-- CPU Usage -->
            <div class="flex items-center gap-3">
              <div class="flex flex-col items-end">
                <span class="text-sm font-semibold text-base-content">CPU</span>
                <span class="text-xs text-base-content/60">{@cpus_max}% Max</span>
              </div>
              <div class="flex items-center gap-2">
                <progress class="progress progress-warning w-20 h-2" value={@cpus_used} max="100">
                </progress>
                <span class="text-sm font-bold text-warning min-w-[3rem] text-right">{@cpu}%</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp host_system_image(system) do
    down_case_system = String.downcase(system)

    cond do
      String.contains?(down_case_system, "macos") ->
        "mac.png"

      String.contains?(down_case_system, "linux") ->
        "linux.png"

      String.contains?(down_case_system, "win") ->
        "windows.png"

      true ->
        "unknown.png"
    end
  end
end
