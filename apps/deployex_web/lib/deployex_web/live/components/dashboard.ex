defmodule DeployexWeb.Components.Dashboard do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component
  alias DeployexWeb.Components.ApplicationCard
  alias DeployexWeb.Components.DeployexCard
  alias DeployexWeb.Helper

  attr :applications, :list, required: true

  attr :monitoring, :list,
    default: [
      {:memory,
       %{enable_restart: true, warning_threshold_percent: 80, restart_threshold_percent: 90}},
      {:atom,
       %{enable_restart: true, warning_threshold_percent: 50, restart_threshold_percent: 90}},
      {:process,
       %{enable_restart: true, warning_threshold_percent: 50, restart_threshold_percent: 90}}
    ]

  def content(assigns) do
    {deployex, monitored_apps} =
      case Enum.split_with(assigns.applications, fn app -> app.name == "deployex" end) do
        {[deployex], monitored_apps} ->
          {deployex, monitored_apps}

        _ ->
          {nil, []}
      end

    assigns =
      assigns
      |> assign(:restart_path, ~p"/applications/deployex/deployex/restart")
      |> assign(:deployex, deployex)
      |> assign(:monitored_apps, monitored_apps)

    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
      <DeployexCard.content
        :if={@deployex}
        deployex={@deployex}
        monitoring={@monitoring}
        restart_path={~p"/applications/deployex/deployex/restart"}
      />

      <div
        :if={@deployex != nil and @deployex.metadata}
        id={Helper.normalize_id("button-deployex-config")}
        class="col-span-2 mt-6"
      >
        <div phx-mounted={
          JS.transition(
            {"first:ease-in duration-300", "first:opacity-0 first:p-0 first:h-0",
             "first:opacity-100"},
            time: 300
          )
        }>
          <!-- Modern Header -->
          <div class="flex items-center gap-3 mb-6">
            <div class="w-8 h-8 bg-primary/10 border border-primary/20 rounded-lg flex items-center justify-center">
              <svg class="w-4 h-4 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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
            <h3 class="text-lg font-semibold text-base-content">Configuration</h3>
            <div class="flex-1"></div>
            <div class="badge badge-primary badge-sm">Active</div>
          </div>

          <.app_config metadata={@deployex.metadata} />
        </div>
      </div>
      <%= for app <- @monitored_apps do %>
        <ApplicationCard.content
          application={app}
          monitoring={@monitoring}
          restart_path={~p"/applications/#{app.name}/#{app.sname}/restart"}
        />
      <% end %>
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

  defp app_config(assigns) do
    applications = Map.keys(assigns.metadata)

    assigns =
      assigns
      |> assign(applications: applications)

    ~H"""
    <div class="space-y-6">
      <%= for app <- @applications do %>
        <div class="bg-base-100 border border-base-300 rounded-xl p-6 shadow-sm hover:shadow-md transition-all duration-200">
          <!-- App Header -->
          <div class="flex items-center justify-between mb-6">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 bg-primary/10 border border-primary/20 rounded-xl flex items-center justify-center">
                <span class="text-lg font-mono font-bold text-primary">{String.first(app)}</span>
              </div>
              <div>
                <h4 class="text-lg font-semibold text-base-content">{app}</h4>
                <p class="text-sm text-base-content/70">Application Instance</p>
              </div>
            </div>
            <div class="flex items-center gap-2 bg-success/10 border border-success/20 rounded-full px-3 py-1">
              <div class="w-2 h-2 bg-success rounded-full animate-pulse"></div>
              <span class="text-sm text-success font-medium">Running</span>
            </div>
          </div>
          <!-- Configuration Grid -->
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- Mode Section -->
            <div class="bg-base-200 border border-base-300 rounded-lg p-4">
              <.mode
                name={app}
                mode={@metadata[app].mode}
                manual_version={@metadata[app].manual_version}
                versions={@metadata[app].versions}
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
                  id={Helper.normalize_id("app-versions-#{app}")}
                  phx-click="app-versions-click"
                  phx-value-name={app}
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
            <!-- Last Ghosted Section -->
            <div class="bg-base-200 border border-base-300 rounded-lg p-4">
              <%= if @metadata[app].last_ghosted_version && @metadata[app].last_ghosted_version != "-/-" do %>
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
                  <div class="bg-warning/10 border border-warning/20 rounded-lg px-3 py-2">
                    <span class="text-sm font-mono text-warning-content">
                      {@metadata[app].last_ghosted_version}
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
        </div>
      <% end %>
    </div>
    """
  end
end
