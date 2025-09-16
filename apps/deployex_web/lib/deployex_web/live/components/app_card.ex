defmodule DeployexWeb.Components.AppCard do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component
  alias DeployexWeb.Components.CopyToClipboard
  alias DeployexWeb.Helper

  # NOTE: This structure is derived from the Deployer.Status structure
  attr :supervisor, :boolean, required: true
  attr :status, :atom, required: true
  attr :node, :string, required: true
  attr :port, :integer, required: true
  attr :sname, :integer, required: true
  attr :language, :string, required: true
  attr :crash_restart_count, :integer, required: true
  attr :force_restart_count, :integer, required: true
  attr :name, :string, required: true
  attr :version, :string, required: true
  attr :uptime, :string, required: true
  attr :otp, :atom, required: true
  attr :tls, :atom, required: true
  attr :last_deployment, :atom, required: true
  attr :restart_path, :string, required: true
  attr :metadata, :map, required: true

  def content(assigns) do
    ~H"""
    <div
      id={Helper.normalize_id("button-app-card-#{@sname}")}
      class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow duration-200"
    >
      <div phx-mounted={
        JS.transition(
          {"first:ease-in duration-300", "first:opacity-0 first:p-0 first:h-0", "first:opacity-100"},
          time: 300
        )
      }>
        <.header_card status={@status} version={@version} sname={@sname} restart_path={@restart_path} />

        <div class="card-body p-8">
          <!-- App Header -->
          <div class="flex items-center gap-6 mb-8">
            <div class="avatar">
              <div class="w-20 h-20 rounded-3xl bg-base-200/30 flex items-center justify-center">
                <img src={"/images/#{@language}.ico"} alt="" class="w-12 h-12" />
              </div>
            </div>
            <div class="flex-1">
              <h1 class="text-3xl font-bold text-base-content mb-2">{@name}</h1>
              <div class="badge badge-neutral badge-lg">Application</div>
            </div>
          </div>
          
    <!-- App Details Grid -->
          <div class="space-y-4">
            <div class="bg-base-200 border border-base-300 rounded-lg p-3 hover:bg-base-100/30 transition-colors">
              <div class="flex items-center gap-2 mb-2">
                <svg
                  class="w-3 h-3 text-base-content/60"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2"
                  >
                  </path>
                </svg>
                <div class="text-xs font-medium text-base-content/60">Node</div>
              </div>
              <div class="flex text-sm font-mono text-base-content/90 truncate gap-2">
                <CopyToClipboard.content id={"c2c-node-messages-#{@sname}"} message={@node} />
                {@node}
              </div>
            </div>

            <div class="grid grid-cols-3 gap-3">
              <div class="bg-base-200 border border-base-300 rounded-lg p-3 hover:bg-base-100/30 transition-colors">
                <div class="flex items-center gap-2 mb-2">
                  <svg
                    class="w-3 h-3 text-base-content/60"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0"
                    >
                    </path>
                  </svg>
                  <div class="text-xs font-medium text-base-content/60">Port</div>
                </div>
                <div class="flex text-sm font-mono text-base-content/90 gap-2">
                  <CopyToClipboard.content id={"c2c-port-messages-#{@sname}"} message={@port} />
                  {@port}
                </div>
              </div>

              <div class="bg-base-200 border border-base-300 rounded-lg p-3 hover:bg-base-100/30 transition-colors">
                <div class="flex items-center gap-2 mb-2">
                  <svg
                    class="w-3 h-3 text-base-content/60"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"
                    >
                    </path>
                  </svg>
                  <div class="text-xs font-medium text-base-content/60">OTP Connection</div>
                </div>
                <.connected? status={@otp} />
              </div>

              <div
                :if={@supervisor}
                class="bg-base-200 border border-base-300 rounded-lg p-3 hover:bg-base-100/30 transition-colors"
              >
                <div class="flex items-center gap-2 mb-2">
                  <svg
                    class="w-3 h-3 text-base-content/60"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
                    >
                    </path>
                  </svg>
                  <div class="text-xs font-medium text-base-content/60">mTLS</div>
                </div>
                <.supported? status={@tls} />
              </div>

              <div
                :if={not @supervisor}
                class="bg-base-200 border border-base-300 rounded-lg p-3 hover:bg-base-100/30 transition-colors"
              >
                <div class="flex items-center gap-2 mb-2">
                  <svg
                    class="w-3 h-3 text-error"
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
                  <div class="text-xs font-medium text-base-content/60">Crash Restarts</div>
                </div>
                <.restarts restarts={@crash_restart_count} />
              </div>
            </div>
            <div class="grid grid-cols-3 gap-3">
              <div
                :if={@last_deployment}
                class="bg-base-200 border border-base-300 rounded-lg p-3 hover:bg-base-100/30 transition-colors"
              >
                <div class="flex items-center gap-2 mb-2">
                  <svg class="w-3 h-3 text-info" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M7 4V2a1 1 0 011-1h8a1 1 0 011 1v2h4a1 1 0 110 2h-1v12a2 2 0 01-2 2H6a2 2 0 01-2-2V6H3a1 1 0 110-2h4zM6 6v12h12V6H6zm3 3a1 1 0 112 0v6a1 1 0 11-2 0V9zm4 0a1 1 0 112 0v6a1 1 0 11-2 0V9z"
                    >
                    </path>
                  </svg>
                  <div class="text-xs font-medium text-base-content/60">Last Deployment</div>
                </div>
                <.deployment deployment={@last_deployment} />
              </div>

              <div class="bg-base-200 border border-base-300 rounded-lg p-3">
                <div class="flex items-center gap-2 mb-2">
                  <svg
                    class="w-3 h-3 text-success"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    >
                    </path>
                  </svg>
                  <div class="text-xs font-medium text-success">Uptime</div>
                </div>
                <div class="text-sm font-semibold text-success">{@uptime}</div>
              </div>

              <div
                :if={@supervisor == false}
                class="bg-base-200 border border-base-300 rounded-lg p-3 hover:bg-base-100/30 transition-colors"
              >
                <div class="flex items-center gap-2 mb-2">
                  <svg
                    class="w-3 h-3 text-warning"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                    >
                    </path>
                  </svg>
                  <div class="text-xs font-medium text-base-content/60">Force Restarts</div>
                </div>
                <.restarts restarts={@force_restart_count} />
              </div>
            </div>
          </div>
          
    <!-- Action Buttons -->
          <div class="pt-6 border-t border-base-200">
            <!-- Primary Actions Row -->
            <div class="flex gap-2 mb-3">
              <button
                id={Helper.normalize_id("app-log-stdout-#{@sname}")}
                phx-click="app-log-click"
                phx-value-node={@node}
                phx-value-name={@name}
                phx-value-sname={@sname}
                phx-value-std="stdout"
                type="button"
                class="btn btn-sm bg-success/10 text-success border-success/20 hover:bg-success/20 hover:border-success/30 hover:scale-105 transition-all duration-200 flex-1 tooltip"
                data-tip="View standard output logs"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  >
                  </path>
                </svg>
                <span class="font-medium">stdout</span>
              </button>

              <button
                id={Helper.normalize_id("app-terminal-#{@sname}")}
                phx-click="app-terminal-click"
                phx-value-node={@node}
                phx-value-name={@name}
                phx-value-sname={@sname}
                phx-value-std="terminal"
                type="button"
                class="btn btn-sm bg-primary/10 text-primary border-primary/20 hover:bg-primary/20 hover:border-primary/30 hover:scale-105 transition-all duration-200 tooltip"
                data-tip="Open interactive terminal"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                  >
                  </path>
                </svg>
              </button>

              <button
                id={Helper.normalize_id("app-log-stderr-#{@sname}")}
                phx-click="app-log-click"
                phx-value-node={@node}
                phx-value-name={@name}
                phx-value-sname={@sname}
                phx-value-std="stderr"
                type="button"
                class="btn btn-sm bg-error/10 text-error border-error/20 hover:bg-error/20 hover:border-error/30 hover:scale-105 transition-all duration-200 flex-1 tooltip"
                data-tip="View error logs"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  >
                  </path>
                </svg>
                <span class="font-medium">stderr</span>
              </button>
            </div>
            
    <!-- Secondary Actions Row -->
            <div :if={not @supervisor} class="flex">
              <button
                id={Helper.normalize_id("app-versions-#{@sname}")}
                phx-click="app-versions-click"
                phx-value-name={@name}
                phx-value-sname={@sname}
                type="button"
                class="btn btn-sm bg-info/10 text-info border-info/20 hover:bg-info/20 hover:border-info/30 hover:scale-105 transition-all duration-200 w-full tooltip"
                data-tip="Manage application versions"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M7 4V2a1 1 0 011-1h8a1 1 0 011 1v2m-9 4v10a2 2 0 002 2h6a2 2 0 002-2V8M7 8h10M9 12h6m-6 4h6"
                  >
                  </path>
                </svg>
                <span class="font-medium">Versions</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div
      :if={@supervisor and @metadata}
      id={Helper.normalize_id("button-app-config")}
      class="col-span-2 mt-6"
    >
      <div phx-mounted={
        JS.transition(
          {"first:ease-in duration-300", "first:opacity-0 first:p-0 first:h-0", "first:opacity-100"},
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

        <.app_config metadata={@metadata} />
      </div>
    </div>
    """
  end

  defp connected?(assigns) do
    ~H"""
    <%= if @status == :connected do %>
      <div class="flex items-center gap-1">
        <div class="w-2 h-2 bg-success rounded-full"></div>
        <span class="text-sm font-medium text-success">Connected</span>
      </div>
    <% else %>
      <div class="flex items-center gap-1">
        <div class="w-2 h-2 bg-error rounded-full"></div>
        <span class="text-sm font-medium text-error">Disconnected</span>
      </div>
    <% end %>
    """
  end

  defp supported?(assigns) do
    ~H"""
    <%= if @status == :supported do %>
      <div class="flex items-center gap-1">
        <div class="w-2 h-2 bg-success rounded-full"></div>
        <span class="text-sm font-medium text-success">Supported</span>
      </div>
    <% else %>
      <div class="flex items-center gap-1">
        <div class="w-2 h-2 bg-error rounded-full"></div>
        <span class="text-sm font-medium text-error">Not Supported</span>
      </div>
    <% end %>
    """
  end

  defp restarts(assigns) do
    ~H"""
    <%= cond do %>
      <% @restarts > 0 -> %>
        <div class="flex items-center gap-1">
          <div class="w-2 h-2 bg-error rounded-full animate-pulse"></div>
          <span class="text-sm font-semibold text-error">{@restarts}</span>
        </div>
      <% true -> %>
        <div class="flex items-center gap-1">
          <div class="w-2 h-2 bg-neutral rounded-full"></div>
          <span class="text-sm font-medium text-neutral">{@restarts}</span>
        </div>
    <% end %>
    """
  end

  defp deployment(assigns) do
    ~H"""
    <%= if @deployment == :full_deployment do %>
      <div class="flex items-center gap-1">
        <div class="w-2 h-2 bg-primary rounded-full"></div>
        <span class="text-sm font-medium text-primary">Full Deployment</span>
      </div>
    <% else %>
      <div class="flex items-center gap-1">
        <div class="w-2 h-2 bg-secondary rounded-full"></div>
        <span class="text-sm font-medium text-secondary">Hot Upgrade</span>
      </div>
    <% end %>
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

  defp restart_button(assigns) do
    ~H"""
    <.link id={Helper.normalize_id("app-restart-#{@sname}")} patch={@restart_path}>
      <button
        type="button"
        class="btn btn-sm btn-circle bg-error/10 border-error/20 text-error hover:bg-error/20 hover:border-error/30 hover:scale-110 transition-all duration-200 tooltip tooltip-left"
        data-tip="Restart Application"
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
      </button>
    </.link>
    """
  end

  defp header_card(assigns) do
    ~H"""
    <%= cond do %>
      <% @status == :running and @version != nil -> %>
        <div class="flex items-center justify-between p-4 bg-success/10 border-b border-success/20 rounded-t-lg">
          <div class="flex items-center gap-2">
            <div class="w-2 h-2 bg-success rounded-full animate-pulse"></div>
            <span class="text-sm font-semibold text-success">Running</span>
          </div>
          <span class="font-mono text-sm font-medium text-success">{@version}</span>
          <.restart_button sname={@sname} restart_path={@restart_path} />
        </div>
      <% @status == :pre_commands -> %>
        <div class="flex items-center justify-between p-4 bg-warning/10 border-b border-warning/20 rounded-t-lg">
          <div class="flex items-center gap-2">
            <div class="w-2 h-2 bg-warning rounded-full animate-pulse"></div>
            <span class="text-sm font-semibold text-warning">Pre-commands</span>
          </div>
          <.restart_button sname={@sname} restart_path={@restart_path} />
        </div>
      <% @status == :starting and @version != nil -> %>
        <div class="flex items-center justify-between p-4 bg-warning/10 border-b border-warning/20 rounded-t-lg">
          <div class="flex items-center gap-2">
            <div class="w-2 h-2 bg-warning rounded-full animate-pulse"></div>
            <span class="text-sm font-semibold text-warning">Starting</span>
          </div>
          <span class="font-mono text-sm font-medium text-warning">{@version}</span>
          <.restart_button sname={@sname} restart_path={@restart_path} />
        </div>
      <% true -> %>
        <div class="flex items-center justify-center p-4 bg-base-200/50 border-b border-base-200 rounded-t-lg">
          <div class="flex items-center gap-2">
            <div class="w-2 h-2 bg-base-content/30 rounded-full animate-pulse"></div>
            <span class="text-sm font-medium text-base-content/60">Version not set</span>
          </div>
        </div>
    <% end %>
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
