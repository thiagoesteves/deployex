defmodule DeployexWeb.Components.SystemBar do
  @moduledoc """
  The tech stack, the host system and its uptime. The top bar shows the host CPU and memory.
  """
  use Phoenix.Component

  attr :info, :map, required: true

  def content(assigns) do
    info = assigns.info

    assigns =
      if is_nil(info) or is_nil(info.memory_free) or is_nil(info.cpu) do
        assigns
        |> assign(system: "--")
        |> assign(description: "--")
        |> assign(uptime: "--")
      else
        assigns
        |> assign(system: info.host)
        |> assign(description: info.description)
        |> assign(uptime: Map.get(info, :uptime) || "--")
      end

    ~H"""
    <div class="bg-base-100 shadow-sm">
      <div id="live-memory-bar" class="navbar h-16 px-8" role="banner">
        <div class="navbar-start">
          <div class="flex items-center gap-8">
            <!-- Tech Stack -->
            <div class="flex items-center gap-6">
              <div class="flex items-center gap-3">
                <img alt="OTP" class="erlang-logo w-8 h-8" />
                <div class="flex flex-col">
                  <span class="text-sm font-semibold text-base-content">OTP</span>
                  <span class="text-xs text-base-content/60">{System.otp_release()}</span>
                </div>
              </div>

              <div class="flex items-center gap-3">
                <img alt="Elixir" class="elixir-logo w-8 h-8" />
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
            <!-- Uptime -->
            <div class="flex items-center gap-3">
              <div class="flex flex-col items-end">
                <span class="text-sm font-semibold text-base-content">Uptime</span>
                <span class="text-xs text-base-content/60">{@uptime}</span>
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
