defmodule DeployexWeb.Components.Monitoring do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component

  alias DeployexWeb.Helper

  attr :monitoring, :list, required: true
  attr :id, :string, required: true

  def content(assigns) do
    ~H"""
    <div
      :if={has_monitoring_enabled?(@monitoring)}
      id={Helper.normalize_id("button-#{@id}-monitoring")}
    >
      <!-- Monitoring Header -->
      <div class="flex items-center gap-3 mb-6">
        <div class="w-8 h-8 bg-info/10 border border-info/20 rounded-lg flex items-center justify-center">
          <svg class="w-4 h-4 text-info" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
            >
            </path>
          </svg>
        </div>
        <h3 class="text-lg font-semibold text-base-content">Resource Monitoring</h3>
        <div class="flex-1"></div>
        <div class="badge badge-info badge-sm">Active</div>
      </div>

      <.monitoring_grid monitoring={@monitoring} />
    </div>
    """
  end

  # Helper function to check if monitoring section should be shown
  defp has_monitoring_enabled?(monitoring) do
    monitoring != [] and monitoring != nil
  end

  defp monitoring_grid(assigns) do
    enabled_monitoring =
      Enum.filter(assigns.monitoring, fn {_name, config} -> config.enable_restart end)

    assigns = assign(assigns, :enabled_monitoring, enabled_monitoring)

    ~H"""
    <%= if @enabled_monitoring == [] do %>
      <div class="bg-base-100 border border-base-300 rounded-xl  shadow-sm">
        <div class="flex items-center justify-center gap-3 py-8">
          <div class="w-12 h-12 bg-base-200 border border-base-300 rounded-lg flex items-center justify-center">
            <svg
              class="w-6 h-6 text-base-content/40"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636"
              >
              </path>
            </svg>
          </div>
          <div>
            <h4 class="text-base font-semibold text-base-content/60">Monitoring Disabled</h4>
            <p class="text-sm text-base-content/40">No resource monitoring is currently enabled</p>
          </div>
        </div>
      </div>
    <% else %>
      <% cols = length(@enabled_monitoring) %>
      <div class={["grid gap-4", "grid-cols-#{cols}"]}>
        <%= for {resource_name, config} <- @enabled_monitoring do %>
          <.monitoring_card resource_name={resource_name} config={config} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp monitoring_card(assigns) do
    # For demonstration, using a placeholder current_usage
    # In production, this would come from your monitoring system
    current_usage = Map.get(assigns.config, :current_usage, 45)

    # Determine status based on current usage
    status =
      cond do
        current_usage >= assigns.config.restart_threshold_percent -> :critical
        current_usage >= assigns.config.warning_threshold_percent -> :warning
        true -> :ok
      end

    {status_color, status_text} =
      case status do
        :ok -> {"success", "Normal"}
        :warning -> {"warning", "Warning"}
        :critical -> {"error", "Critical"}
      end

    assigns =
      assigns
      |> assign(:resource_display, format_resource_name(assigns.resource_name))
      |> assign(:current_usage, current_usage)
      |> assign(:status, status)
      |> assign(:status_color, status_color)
      |> assign(:status_text, status_text)

    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl p-5 shadow-sm hover:shadow-md transition-all duration-200">
      <!-- Resource Header -->
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-3">
          <div class={"w-10 h-10 rounded-lg flex items-center justify-center #{get_resource_bg(@resource_name)}"}>
            <.resource_icon resource_name={@resource_name} />
          </div>
          <div>
            <h4 class="text-base font-semibold text-base-content">{@resource_display}</h4>
            <p class="text-xs text-base-content/60">Auto-restart enabled</p>
          </div>
        </div>
        <!-- Status Badge -->
        <div class={"badge badge-#{@status_color} badge-sm gap-1"}>
          <div class={"w-1.5 h-1.5 bg-#{@status_color}-content rounded-full animate-pulse"}></div>
          {@status_text}
        </div>
      </div>
      
    <!-- Combined Progress Bar -->
      <div class="space-y-3">
        <div class="bg-base-200 border border-base-300 rounded-lg p-4">
          <!-- Current Usage Display -->
          <div class="flex items-center justify-between mb-3">
            <span class="text-sm font-medium text-base-content">Current Usage</span>
            <span class={"text-lg font-bold font-mono text-#{@status_color}"}>
              {@current_usage}%
            </span>
          </div>
          <!-- Visual Progress Bar with Threshold Markers -->
          <div class="relative">
            <!-- Background bar -->
            <div class="w-full bg-base-300 rounded-full h-8 relative overflow-visible">
              <!-- Warning threshold marker -->
              <div
                class="absolute top-0 bottom-0 w-0.5 bg-warning z-10"
                style={"left: #{@config.warning_threshold_percent}%"}
              >
                <div class="absolute -top-6 left-1/2 transform -translate-x-1/2 text-xs font-medium text-warning whitespace-nowrap">
                  {@config.warning_threshold_percent}%
                </div>
              </div>
              <!-- Restart threshold marker -->
              <div
                class="absolute top-0 bottom-0 w-0.5 bg-error z-10"
                style={"left: #{@config.restart_threshold_percent}%"}
              >
                <div class="absolute -top-6 left-1/2 transform -translate-x-1/2 text-xs font-medium text-error whitespace-nowrap">
                  {@config.restart_threshold_percent}%
                </div>
              </div>
              <!-- Current usage fill -->
              <div
                class={"rounded-full h-8 transition-all duration-500 flex items-center justify-end pr-2 bg-#{@status_color}"}
                style={"width: #{@current_usage}%"}
              >
                <%= if @current_usage > 10 do %>
                  <span class="text-xs font-bold text-white">
                    {@current_usage}%
                  </span>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- Threshold Legend -->
          <div class="grid grid-cols-2 gap-2 mt-4 pt-3 border-t border-base-300">
            <div class="flex items-center gap-2">
              <div class="w-3 h-3 bg-warning rounded"></div>
              <span class="text-xs text-base-content/70">
                Warning: {@config.warning_threshold_percent}%
              </span>
            </div>
            <div class="flex items-center gap-2">
              <div class="w-3 h-3 bg-error rounded"></div>
              <span class="text-xs text-base-content/70">
                Restart: {@config.restart_threshold_percent}%
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp get_resource_bg(resource_name) do
    case resource_name do
      :memory -> "bg-purple-500/10 border border-purple-500/20"
      :atom -> "bg-blue-500/10 border border-blue-500/20"
      :process -> "bg-green-500/10 border border-green-500/20"
      :port -> "bg-orange-500/10 border border-orange-500/20"
      _ -> "bg-primary/10 border border-primary/20"
    end
  end

  defp resource_icon(assigns) do
    icon_svg =
      case assigns.resource_name do
        :memory ->
          ~H"""
          <svg class="w-5 h-5 text-purple-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
            >
            </path>
          </svg>
          """

        :atom ->
          ~H"""
          <svg class="w-5 h-5 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01"
            >
            </path>
          </svg>
          """

        :process ->
          ~H"""
          <svg class="w-5 h-5 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2z"
            >
            </path>
          </svg>
          """

        :port ->
          ~H"""
          <svg class="w-5 h-5 text-orange-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
            >
            </path>
          </svg>
          """

        _ ->
          ~H"""
          <svg class="w-5 h-5 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
            >
            </path>
          </svg>
          """
      end

    assigns = assign(assigns, :icon_svg, icon_svg)

    ~H"""
    {@icon_svg}
    """
  end

  defp format_resource_name(resource_name) do
    case resource_name do
      :memory ->
        "Memory"

      :atom ->
        "Atom Table"

      :process ->
        "Process Count"

      :port ->
        "Port Count"

      _ ->
        resource_name
        |> Atom.to_string()
        |> String.capitalize()
        |> String.replace("_", " ")
    end
  end
end
