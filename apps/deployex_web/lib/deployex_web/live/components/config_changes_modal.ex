defmodule DeployexWeb.Components.ConfigChangesModal do
  @moduledoc """
  Modal component for displaying pending configuration changes in a human-readable format.
  """
  use DeployexWeb, :html
  use Phoenix.Component

  alias DeployexWeb.Helper
  alias Foundation.Config.Changes

  attr :id, :string, required: true
  attr :pending_changes, Changes, required: true
  attr :on_apply, :string, required: true
  attr :on_cancel, :string, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={"#{@id}-config-changes-modal"}
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm"
      phx-window-keydown={@on_cancel}
      phx-key="escape"
    >
      <div class="bg-base-100 rounded-2xl shadow-2xl w-full max-w-4xl max-h-[90vh] overflow-hidden">
        <!-- Header -->
        <div class="bg-warning/10 border-b border-warning/20 p-6">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 bg-warning/20 rounded-full flex items-center justify-center">
                <svg
                  class="w-6 h-6 text-warning"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
                  >
                  </path>
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                  >
                  </path>
                </svg>
              </div>
              <div>
                <h2 class="text-2xl font-bold text-warning">Configuration Changes Detected</h2>
                <p class="text-sm text-base-content/60">
                  {format_timestamp(@pending_changes.timestamp)} • {@pending_changes.changes_count} change(s) pending
                </p>
              </div>
            </div>
            <button
              phx-click={@on_cancel}
              id={Helper.normalize_id("#{@id}-config-changes-escape")}
              type="button"
              class="btn btn-sm btn-circle btn-ghost hover:bg-warning/20"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                >
                </path>
              </svg>
            </button>
          </div>
        </div>
        <!-- Content -->
        <div class="overflow-y-auto max-h-[calc(90vh-200px)] p-6">
          <div class="space-y-6">
            <%= for {field, change_data} <- @pending_changes.summary do %>
              <.render_change_section field={field} change_data={change_data} />
            <% end %>
          </div>
        </div>
        <!-- Footer -->
        <div class="bg-base-200 border-t border-base-300 p-6 flex items-center justify-between">
          <div class="flex items-center gap-2 text-sm text-base-content/60">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              >
              </path>
            </svg>
            <span>Review changes carefully before applying</span>
          </div>
          <div class="flex gap-3">
            <button
              phx-click={@on_cancel}
              id={Helper.normalize_id("#{@id}-config-changes-cancel")}
              type="button"
              class="btn btn-ghost hover:bg-base-300"
            >
              Cancel
            </button>
            <button
              phx-click={@on_apply}
              id={Helper.normalize_id("#{@id}-config-changes-apply")}
              type="button"
              class="btn bg-warning text-warning-content hover:bg-warning/80 gap-2"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                >
                </path>
              </svg>
              Apply Changes
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_change_section(%{field: :applications} = assigns) do
    ~H"""
    <div class="bg-base-200 rounded-lg p-4 border border-base-300">
      <div class="flex items-center gap-2 mb-4">
        <svg class="w-5 h-5 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
          >
          </path>
        </svg>
        <h3 class="text-lg font-bold text-base-content">Applications</h3>
      </div>
      <%= for {app_name, app_changes} <- @change_data.details do %>
        <.render_app_change app_name={app_name} app_changes={app_changes} />
      <% end %>
    </div>
    """
  end

  defp render_change_section(%{field: :monitoring} = assigns) do
    ~H"""
    <div class="bg-base-200 rounded-lg p-4 border border-base-300">
      <div class="flex items-center gap-2 mb-4">
        <svg class="w-5 h-5 text-info" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
          >
          </path>
        </svg>
        <h3 class="text-lg font-bold text-base-content">Monitoring Configuration</h3>
      </div>
      <div class="space-y-3">
        <% metrics = (Keyword.keys(@change_data.old) ++ Keyword.keys(@change_data.new)) |> Enum.uniq() %>
        <%= for mon_type <- metrics do %>
          <.render_monitoring_change
            type={mon_type}
            old={find_monitoring_by_type(@change_data.old, mon_type)}
            new={find_monitoring_by_type(@change_data.new, mon_type)}
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp render_change_section(%{field: field} = assigns) do
    field_name = format_field_name(field)

    assigns =
      assigns
      |> assign(:field_name, field_name)

    ~H"""
    <div class="bg-base-200 rounded-lg p-4 border border-base-300">
      <div class="flex items-center gap-2 mb-3">
        <svg class="w-5 h-5 text-accent" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4"
          >
          </path>
        </svg>
        <h3 class="text-lg font-bold text-base-content">{@field_name}</h3>
      </div>
      <div class="grid grid-cols-2 gap-4">
        <div class="bg-error/10 border border-error/20 rounded-lg p-3">
          <div class="text-xs font-semibold text-error mb-2">Current Value</div>
          <div class="font-mono text-sm text-error line-through max-h-24 overflow-y-auto break-words">
            {format_value(@field, @change_data.old)}
          </div>
        </div>
        <div class="bg-success/10 border border-success/20 rounded-lg p-3">
          <div class="text-xs font-semibold text-success mb-2">New Value</div>
          <div class="font-mono text-sm text-base-content max-h-24 overflow-y-auto break-words">
            {format_value(@field, @change_data.new)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_app_change(%{app_changes: %{status: :added}} = assigns) do
    ~H"""
    <div class="ml-4 mb-3 bg-success/10 border-l-4 border-success rounded-lg p-3">
      <div class="flex items-center gap-2 mb-2">
        <div class="w-2 h-2 bg-success rounded-full"></div>
        <span class="font-semibold text-success">Added: {@app_name}</span>
      </div>
      <div class="text-sm text-base-content/70 ml-4">
        New application will be deployed
      </div>
    </div>
    """
  end

  defp render_app_change(%{app_changes: %{status: :removed}} = assigns) do
    ~H"""
    <div class="ml-4 mb-3 bg-error/10 border-l-4 border-error rounded-lg p-3">
      <div class="flex items-center gap-2 mb-2">
        <div class="w-2 h-2 bg-error rounded-full"></div>
        <span class="font-semibold text-error">Removed: {@app_name}</span>
      </div>
      <div class="text-sm text-base-content/70 ml-4">
        Application will be stopped and removed
      </div>
    </div>
    """
  end

  defp render_app_change(%{app_changes: %{status: :modified}} = assigns) do
    ~H"""
    <div class="ml-4 mb-3 bg-warning/10 border-l-4 border-warning rounded-lg p-3">
      <div class="flex items-center gap-2 mb-3">
        <div class="w-2 h-2 bg-warning rounded-full"></div>
        <span class="font-semibold text-warning">Modified: {@app_name}</span>
      </div>
      <div class="flex items-start gap-2 text-sm">
        <svg
          class="w-4 h-4 text-error flex-shrink-0 mt-0.5"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
          />
        </svg>
        <span class="text-base-content/80">
          Application modifications require a new full deployment to take effect.
        </span>
      </div>
      <div class="ml-4 space-y-2 mt-2">
        <%= for {field, change} <- @app_changes.changes do %>
          <.render_change_section field={field} change_data={change} />
        <% end %>
      </div>
    </div>
    """
  end

  defp render_monitoring_change(%{new: nil} = assigns) do
    ~H"""
    <div class="bg-error/10 border-l-4 border-error rounded-lg p-3">
      <div class="flex items-center gap-2">
        <div class="w-2 h-2 bg-error rounded-full"></div>
        <span class="font-semibold text-error">Removed: {String.upcase(to_string(@type))}</span>
      </div>

      <div class="flex gap-2 items-center mt-1">
        <span class="text-error line-through">{format_metric(@old)}</span>
      </div>
    </div>
    """
  end

  defp render_monitoring_change(%{old: nil} = assigns) do
    ~H"""
    <div class="bg-warning/10 border-l-4 border-warning rounded-lg p-3">
      <div class="flex items-center gap-2 mb-2">
        <div class="w-2 h-2 bg-warning rounded-full"></div>
        <span class="font-semibold text-success">Added: {String.upcase(to_string(@type))}</span>
      </div>

      <div class="flex gap-2 items-center mt-1">
        <span class="text-success">{format_metric(@new)}</span>
      </div>
    </div>
    """
  end

  defp render_monitoring_change(assigns) do
    ~H"""
    <div class="bg-warning/10 border-l-4 border-warning rounded-lg p-3">
      <div class="flex items-center gap-2 mb-2">
        <div class="w-2 h-2 bg-warning rounded-full"></div>
        <span class="font-semibold text-warning">Modified: {String.upcase(to_string(@type))}</span>
      </div>

      <div class="flex gap-2 items-center mt-1">
        <span class="text-error line-through">{format_metric(@old)}</span>
        <span class="text-base-content/50">→</span>
        <span class="text-base-content">{format_metric(@new)}</span>
      </div>
    </div>
    """
  end

  defp format_metric(%{
         enable_restart: enabled,
         warning_threshold_percent: warning_threshold_percent,
         restart_threshold_percent: restart_threshold_percent
       }) do
    "enabled: #{enabled} warning: #{warning_threshold_percent}% critical: #{restart_threshold_percent}%"
  end

  # Helper functions
  defp format_field_name(field) do
    field
    |> to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_value(_, []), do: "empty"

  defp format_value(:replica_ports, list) do
    Enum.map_join(list, " ", fn %{key: key, base: base} -> "#{key}=#{base}" end)
  end

  defp format_value(:env, list), do: Enum.join(list, " ")

  defp format_value(_, value), do: to_string(value)

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp find_monitoring_by_type(monitoring_list, type) do
    Enum.find_value(monitoring_list, fn
      {^type, config} -> config
      _ -> nil
    end)
  end
end
