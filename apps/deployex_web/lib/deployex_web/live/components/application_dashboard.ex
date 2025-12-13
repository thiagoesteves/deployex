defmodule DeployexWeb.Components.ApplicationDashboard do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component
  alias DeployexWeb.Components.ApplicationCard
  alias DeployexWeb.Helper

  attr :monitored_app, :map, required: true
  attr :metrics, :map, required: true
  attr :active_sname_tab, :string, required: true

  def content(assigns) do
    # Check if the selected sname still exists
    active_sname_tab =
      Enum.reduce_while(assigns.monitored_app.children, nil, fn %{sname: sname}, acc ->
        cond do
          sname == assigns.active_sname_tab -> {:halt, sname}
          is_nil(acc) -> {:cont, sname}
          true -> {:cont, acc}
        end
      end)

    assigns =
      assigns
      |> assign(:active_sname_tab, active_sname_tab)

    ~H"""
    <div>
      <!-- Modern Header -->
      <div class="bg-base-100  rounded-xl  transition-all duration-200 mt-2">
        <!-- App Header -->
        <div class="flex items-center justify-between mb-6">
          <div class="flex items-center gap-4">
            <div class="w-12 h-12 bg-primary/10 border border-primary/20 rounded-xl flex items-center justify-center">
              <span class="text-lg font-mono font-bold text-primary">
                {String.first(@monitored_app.name)}
              </span>
            </div>
            <div>
              <h4 class="text-lg font-semibold text-base-content">{@monitored_app.name}</h4>
              <p class="text-sm text-base-content/70">Application Instance</p>
            </div>
          </div>
          <div class="flex items-center gap-3">
            <div class="flex items-center gap-2 bg-success/10 border border-success/20 rounded-full px-3 py-1">
              <div class="w-2 h-2 bg-success rounded-full animate-pulse"></div>
              <span class="text-sm text-success font-medium">Running</span>
            </div>
            <.link
              id={Helper.normalize_id("app-full-restart-#{@monitored_app.name}")}
              patch={~p"/applications/#{@monitored_app.name}/restart"}
            >
              <button
                type="button"
                class="btn btn-sm bg-gradient-to-r from-red-500 to-red-600 hover:from-red-600 hover:to-red-700 text-white border-0 rounded-lg transition-all duration-200 hover:scale-105 shadow-md hover:shadow-lg"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                  >
                  </path>
                </svg>
                <svg class="w-4 h-4 -ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
                  >
                  </path>
                </svg>
                Full Restart
              </button>
            </.link>
          </div>
        </div>
        <!-- Configuration Grid -->
        <div class="grid grid-cols-6  gap-6">
          <!-- Mode Section -->
          <div class="bg-base-200 border border-base-300 rounded-lg p-4">
            <.mode
              name={@monitored_app.name}
              mode={@monitored_app.config.mode}
              manual_version={@monitored_app.config.manual_version}
              versions={@monitored_app.config.versions}
            />
          </div>
          <!-- History Section -->
          <div class="bg-base-200 border border-base-300 rounded-lg p-4">
            <div class="space-y-3">
              <div class="flex items-center gap-2">
                <svg class="w-4 h-4 text-info" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                  >
                  </path>
                </svg>
                <span class="text-sm font-medium text-base-content">Version History</span>
              </div>
              <button
                id={Helper.normalize_id("app-versions-#{@monitored_app.name}")}
                phx-click="app-versions-click"
                phx-value-name={@monitored_app.name}
                type="button"
                class="w-full bg-info/10 hover:bg-info/20 border border-info/20 hover:border-info/30 rounded-lg px-4 py-2 text-sm font-medium text-info transition-all duration-200 flex items-center justify-center gap-2"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 5l7 7-7 7"
                  >
                  </path>
                </svg>
                View Versions
              </button>
            </div>
          </div>
          <!-- Replicas Section -->
          <div class="bg-base-200 border border-base-300 rounded-lg p-4 hover:bg-base-100/30 transition-colors">
            <div class="flex items-center gap-2 mb-2">
              <svg class="w-4 h-4 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4"
                >
                </path>
              </svg>
              <span class="text-sm font-medium text-base-content">Replicas</span>
            </div>
            <div class="text-2xl font-bold text-primary">{@monitored_app.replicas}</div>
            <div class="text-xs text-base-content/60 mt-1">Active instances</div>
          </div>
          <!-- Rollback Timeout Section -->
          <div class="bg-base-200 border border-base-300 rounded-lg p-4 hover:bg-base-100/30 transition-colors">
            <div class="flex items-center gap-2 mb-2">
              <svg class="w-4 h-4 text-warning" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                >
                </path>
              </svg>
              <span class="text-sm font-medium text-base-content">Rollback Timeout</span>
              <div
                class="tooltip tooltip-right"
                data-tip="Maximum time allowed before marking a deployment as failed (ghosted version) and triggering an automatic rollback"
              >
                <div class="w-4 h-4 rounded-full bg-warning/20 border border-warning/40 flex items-center justify-center cursor-help hover:bg-warning/30 transition-colors">
                  <span class="text-[10px] font-bold text-warning">?</span>
                </div>
              </div>
            </div>
            <div class="text-2xl font-bold text-warning">
              {Helper.format_ms_to_readable(@monitored_app.deploy_rollback_timeout_ms)}
            </div>
            <div class="text-xs text-base-content/60 mt-1 font-mono">
              {@monitored_app.deploy_rollback_timeout_ms}ms
            </div>
          </div>
          <!-- Schedule Interval Section -->
          <div class="bg-base-200 border border-base-300 rounded-lg p-4 hover:bg-base-100/30 transition-colors">
            <div class="flex items-center gap-2 mb-2">
              <svg class="w-4 h-4 text-info" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                >
                </path>
              </svg>
              <span class="text-sm font-medium text-base-content">Schedule Interval</span>
              <div
                class="tooltip tooltip-right"
                data-tip="Frequency at which the system checks for new versions and triggers deployments"
              >
                <div class="w-4 h-4 rounded-full bg-info/20 border border-info/40 flex items-center justify-center cursor-help hover:bg-info/30 transition-colors">
                  <span class="text-[10px] font-bold text-info">?</span>
                </div>
              </div>
            </div>
            <div class="text-2xl font-bold text-info">
              {Helper.format_ms_to_readable(@monitored_app.deploy_schedule_interval_ms)}
            </div>
            <div class="text-xs text-base-content/60 mt-1 font-mono">
              {@monitored_app.deploy_schedule_interval_ms}ms
            </div>
          </div>
          <!-- Last Ghosted Section -->
          <div class="bg-base-200 border border-base-300 rounded-lg p-4">
            <%= if @monitored_app.config.last_ghosted_version && @monitored_app.config.last_ghosted_version != "-/-" do %>
              <div class="space-y-3">
                <div class="flex items-center gap-2">
                  <svg
                    class="w-4 h-4 text-warning"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
                    >
                    </path>
                  </svg>
                  <span class="text-sm font-medium text-base-content">Last Ghosted</span>
                </div>
                <div class="bg-warning/30 border border-warning/20 rounded-lg px-3 py-2">
                  <span class="text-sm font-mono text-warning-content">
                    {@monitored_app.config.last_ghosted_version}
                  </span>
                </div>
              </div>
            <% else %>
              <div class="space-y-3">
                <div class="flex items-center gap-2">
                  <svg
                    class="w-4 h-4 text-base-content/40"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
                    >
                    </path>
                  </svg>
                  <span class="text-sm font-medium text-base-content/60">Last Ghosted</span>
                </div>
                <div class="bg-base-100 border border-base-300 rounded-lg px-3 py-2">
                  <span class="text-sm text-base-content/60 italic">No ghosted versions</span>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="mt-3 bg-base-300 rounded-lg">
          <div class="tabs tabs-lift bg-base-200 p-1 mb-6 ">
            <%= for child_app <- @monitored_app.children do %>
              <a
                id={"tab-application-#{child_app.sname}"}
                phx-click="swicth-app-tab"
                phx-value-name={@monitored_app.name}
                phx-value-sname={child_app.sname}
                class={[
                  "tab tab-lg",
                  if(@active_sname_tab == child_app.sname, do: "tab-active", else: "")
                ]}
              >
                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                  >
                  </path>
                </svg>
                {child_app.sname}
                <%!-- <div class="badge badge-primary badge-sm ml-2">
            {length(@monitored_apps)}
          </div> --%>
              </a>
              <div class="tab-content bg-base-100 border-base-300 p-6">
                <ApplicationCard.content
                  application={child_app}
                  monitoring={@monitored_app.monitoring}
                  metrics={@metrics}
                  restart_path={~p"/applications/#{child_app.name}/#{child_app.sname}/restart"}
                />
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp mode(assigns) do
    default_class =
      "select select-sm w-full bg-base-100 border-base-300 focus:border-primary focus:outline-none text-sm font-mono rounded-lg"

    {current_value, input_class, mode_icon, mode_color} =
      if assigns.mode == :automatic do
        {"automatic", default_class,
         ~H"""
         <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
           <path
             stroke-linecap="round"
             stroke-linejoin="round"
             stroke-width="2"
             d="M13 10V3L4 14h7v7l9-11h-7z"
           >
           </path>
         </svg>
         """, "success"}
      else
        {assigns.manual_version.version, default_class <> " border-warning",
         ~H"""
         <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
           <path
             stroke-linecap="round"
             stroke-linejoin="round"
             stroke-width="2"
             d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4"
           >
           </path>
         </svg>
         """, "warning"}
      end

    assigns =
      assigns
      |> assign(current_value: current_value)
      |> assign(input_class: input_class)
      |> assign(mode_icon: mode_icon)
      |> assign(mode_color: mode_color)
      |> assign(versions: ["automatic"] ++ assigns.versions)

    ~H"""
    <div class="space-y-3">
      <div class="flex items-center gap-2">
        <div class={"w-4 h-4 text-#{@mode_color}"}>
          {@mode_icon}
        </div>
        <span class="text-sm font-medium text-base-content">Deployment Mode</span>
      </div>
      <form
        id={Helper.normalize_id("#{@name}-form-mode-select")}
        phx-change="app-mode-select"
        phx-value-name={@name}
      >
        <.input
          class={@input_class}
          name="select-mode"
          value={@current_value}
          type="select-undefined-class"
          options={@versions}
        />
      </form>
      <div class={"text-xs text-#{@mode_color} bg-#{@mode_color}/10 border border-#{@mode_color}/20 px-3 py-2 rounded-lg"}>
        <%= if @current_value == "automatic" do %>
          Automatically deploys latest version
        <% else %>
          Manually locked to version {@current_value}
        <% end %>
      </div>
    </div>
    """
  end
end
