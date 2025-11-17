defmodule DeployexWeb.Components.ConfigChangesModal do
  @moduledoc """
  Modal component for displaying pending configuration changes in a human-readable format.
  """
  use DeployexWeb, :html
  use Phoenix.Component

  alias DeployexWeb.Helper
  alias Sentinel.Config.Changes

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
        <!-- Strategy Legend -->
        <div class="bg-base-200/50 border-b border-base-300 px-6 py-4">
          <div class="flex items-center gap-4 text-sm">
            <span class="font-semibold text-base-content/70">Apply Strategies:</span>
            <div class="flex flex-wrap gap-3">
              <.strategy_badge strategy={:immediate} show_description={true} />
              <.strategy_badge strategy={:next_deploy} show_description={true} />
              <.strategy_badge strategy={:full_deploy} show_description={true} />
            </div>
          </div>
        </div>
        <!-- Content -->
        <div class="overflow-y-auto max-h-[calc(90vh-280px)] p-6">
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

  # Strategy badge component with optional tooltip
  attr :strategy, :atom, required: true
  attr :show_description, :boolean, default: false

  defp strategy_badge(assigns) do
    {badge_class, label, description} = strategy_config(assigns.strategy)

    assigns =
      assigns
      |> assign(:badge_class, badge_class)
      |> assign(:label, label)
      |> assign(:description, description)

    ~H"""
    <div
      class={"inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium #{@badge_class} #{if @show_description, do: "tooltip tooltip-bottom", else: ""}"}
      data-tip={if @show_description, do: @description, else: nil}
    >
      <%= case @strategy do %>
        <% :immediate -> %>
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M13 10V3L4 14h7v7l9-11h-7z"
            >
            </path>
          </svg>
        <% :next_deploy -> %>
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
            >
            </path>
          </svg>
        <% :full_deploy -> %>
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
            >
            </path>
          </svg>
      <% end %>
      <span>{@label}</span>
    </div>
    """
  end

  defp strategy_config(:immediate) do
    {
      "bg-success/20 text-success border border-success/30",
      "Immediate",
      "Applied instantly without requiring deployment"
    }
  end

  defp strategy_config(:next_deploy) do
    {
      "bg-info/20 text-info border border-info/30",
      "Next Deploy",
      "Takes effect on the next scheduled deployment"
    }
  end

  defp strategy_config(:full_deploy) do
    {
      "bg-error/20 text-error border border-error/30",
      "Full Deploy",
      "Requires full redeployment with service interruption"
    }
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
      <%= for {name, status} <- @change_data.details do %>
        <.render_app_change name={name} status={status} />
      <% end %>
    </div>
    """
  end

  defp render_change_section(%{field: :monitoring} = assigns) do
    ~H"""
    <div class="bg-base-200 rounded-lg p-4 border border-base-300">
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
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
        <.strategy_badge strategy={@change_data.apply_strategy} />
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
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
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
        <.strategy_badge strategy={@change_data.apply_strategy} />
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

  defp render_app_change(%{status: %{status: :added, apply_strategies: strategies}} = assigns) do
    primary_strategy = List.first(strategies, :immediate)
    assigns = assign(assigns, :primary_strategy, primary_strategy)

    ~H"""
    <div class="ml-4 mb-3 bg-success/10 border-l-4 border-success rounded-lg p-3">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-2">
          <div class="w-2 h-2 bg-success rounded-full"></div>
          <span class="font-semibold text-success">Added: {@name}</span>
        </div>
        <.strategy_badge strategy={@primary_strategy} />
      </div>
      <div class="text-sm text-base-content/70 ml-4">
        New application will be deployed
      </div>
    </div>
    """
  end

  defp render_app_change(%{status: %{status: :removed, apply_strategies: strategies}} = assigns) do
    primary_strategy = List.first(strategies, :immediate)
    assigns = assign(assigns, :primary_strategy, primary_strategy)

    ~H"""
    <div class="ml-4 mb-3 bg-error/10 border-l-4 border-error rounded-lg p-3">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-2">
          <div class="w-2 h-2 bg-error rounded-full"></div>
          <span class="font-semibold text-error">Removed: {@name}</span>
        </div>
        <.strategy_badge strategy={@primary_strategy} />
      </div>
      <div class="text-sm text-base-content/70 ml-4">
        Application will be stopped and removed
      </div>
    </div>
    """
  end

  defp render_app_change(%{status: %{status: :modified, apply_strategies: strategies}} = assigns) do
    has_full_deploy = :full_deploy in strategies
    assigns = assign(assigns, :has_full_deploy, has_full_deploy)

    ~H"""
    <div class="ml-4 mb-3 bg-warning/10 border-l-4 border-warning rounded-lg p-3">
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <div class="w-2 h-2 bg-warning rounded-full"></div>
          <span class="font-semibold text-warning">Modified: {@name}</span>
        </div>
        <div class="flex gap-2">
          <%= for strategy <- Enum.uniq(@status.apply_strategies) do %>
            <.strategy_badge strategy={strategy} />
          <% end %>
        </div>
      </div>

      <%= if @has_full_deploy do %>
        <div class="flex items-start gap-2 text-sm mb-3 bg-error/10 border border-error/20 rounded-lg p-2">
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
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
            />
          </svg>
          <span class="text-error font-medium">
            Some modifications require a full deployment with service interruption
          </span>
        </div>
      <% end %>

      <div class="ml-4 space-y-2 mt-2">
        <%= for {field, change} <- @status.changes do %>
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
    <div class="bg-success/10 border-l-4 border-success rounded-lg p-3">
      <div class="flex items-center gap-2 mb-2">
        <div class="w-2 h-2 bg-success rounded-full"></div>
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
