defmodule DeployexWeb.Components.DeployexCard do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component
  alias Deployer.Github
  alias DeployexWeb.Components.CopyToClipboard
  alias DeployexWeb.Components.Monitoring
  alias DeployexWeb.Helper

  # NOTE: This structure is derived from the Deployer.Status structure
  attr :deployex, :map, required: true
  attr :restart_path, :string, required: true

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
    ~H"""
    <div
      id={Helper.normalize_id("button-deployex-card-#{@deployex.sname}")}
      class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow duration-200"
    >
      <div phx-mounted={
        JS.transition(
          {"first:ease-in duration-300", "first:opacity-0 first:p-0 first:h-0", "first:opacity-100"},
          time: 300
        )
      }>
        <.header_card
          status={@deployex.status}
          version={@deployex.version}
          sname={@deployex.sname}
          restart_path={@restart_path}
          latest_release={@deployex.latest_release}
        />

        <div class="card-body grid grid-cols-3 gap-6">
          <!-- App Header -->
          <div class="gap-6">
            <div class="flex items-center gap-6 mb-8">
              <div class="avatar">
                <div class="w-20 h-20 rounded-3xl bg-base-200/30 flex items-center justify-center">
                  <img src={"/images/#{@deployex.language}.ico"} alt="" class="w-12 h-12" />
                </div>
              </div>
              <div class="flex-1">
                <h1 class="text-3xl font-bold text-base-content mb-2">{@deployex.name}</h1>
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
                  <CopyToClipboard.content
                    id={"c2c-node-messages-#{@deployex.sname}"}
                    message={@deployex.node}
                  />
                  {@deployex.node}
                </div>
              </div>
              <div
                :if={@deployex.ports != []}
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
                      d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0"
                    >
                    </path>
                  </svg>
                  <div class="text-xs font-medium text-base-content/60">Ports</div>
                </div>
                <div class="flex flex-wrap gap-2">
                  <%= for port <- @deployex.ports do %>
                    <div class="inline-flex items-center bg-base-100 border border-base-300 rounded-full overflow-hidden shadow-sm hover:shadow-md transition-all duration-200">
                      <span class="px-3 py-1.5 text-xs font-semibold text-primary bg-primary/10 border-r border-base-300">
                        {port.key}
                      </span>
                      <span class="px-3 py-1.5 text-xs font-mono font-medium text-base-content bg-secondary/10">
                        {port.base}
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
          <div>
            <div class="grid grid-cols-3 grid-rows-2 gap-3 mb-16">
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
                <.connected? status={@deployex.otp} />
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
                      d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
                    >
                    </path>
                  </svg>
                  <div class="text-xs font-medium text-base-content/60">mTLS</div>
                </div>
                <.supported? status={@deployex.tls} />
              </div>

              <div
                :if={@deployex.last_deployment}
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
                <.deployment deployment={@deployex.last_deployment} />
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
                <div class="text-sm font-semibold text-success">{@deployex.uptime}</div>
              </div>
            </div>
            <!-- Action Buttons -->
            <div class="pt-6 border-t border-base-200">
              <!-- Primary Actions Row -->
              <div class="flex gap-2 mb-3">
                <button
                  id={Helper.normalize_id("app-log-stdout-#{@deployex.sname}")}
                  phx-click="app-log-click"
                  phx-value-node={@deployex.node}
                  phx-value-name={@deployex.name}
                  phx-value-sname={@deployex.sname}
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
                  id={Helper.normalize_id("app-terminal-#{@deployex.sname}")}
                  phx-click="app-terminal-click"
                  phx-value-node={@deployex.node}
                  phx-value-name={@deployex.name}
                  phx-value-sname={@deployex.sname}
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
                  id={Helper.normalize_id("app-log-stderr-#{@deployex.sname}")}
                  phx-click="app-log-click"
                  phx-value-node={@deployex.node}
                  phx-value-name={@deployex.name}
                  phx-value-sname={@deployex.sname}
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
            </div>
          </div>
          <!-- Monitoring View -->
          <div>
            <Monitoring.content
              monitoring={[
                {:memory,
                 %{enable_restart: true, warning_threshold_percent: 80, restart_threshold_percent: 90}}
              ]}
              id="deployex"
            />
          </div>
        </div>
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

  defp deployment(assigns) do
    ~H"""
    <%= if @deployment == :full_deployment do %>
      <div class="flex items-center gap-1">
        <div class="w-2 h-2 bg-blue-400 rounded-full"></div>
        <span class="text-sm font-medium text-blue-400">Full Deployment</span>
      </div>
    <% else %>
      <div class="flex items-center gap-1">
        <div class="w-2 h-2 bg-red-400 rounded-full"></div>
        <span class="text-sm font-medium text-red-400">Hot Upgrade</span>
      </div>
    <% end %>
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
          <.version_indicator sname={@sname} latest_release={@latest_release} version={@version} />
          <.restart_button sname={@sname} restart_path={@restart_path} />
        </div>
      <% @status == :pre_commands -> %>
        <div class="flex items-center justify-between p-4 bg-warning/10 border-b border-warning/20 rounded-t-lg">
          <div class="flex items-center gap-2">
            <div class="w-2 h-2 bg-warning rounded-full animate-pulse"></div>
            <span class="text-sm font-semibold text-warning">Pre-commands</span>
          </div>
          <.version_indicator sname={@sname} latest_release={@latest_release} version={@version} />
          <.restart_button sname={@sname} restart_path={@restart_path} />
        </div>
      <% @status == :starting and @version != nil -> %>
        <div class="flex items-center justify-between p-4 bg-warning/10 border-b border-warning/20 rounded-t-lg">
          <div class="flex items-center gap-2">
            <div class="w-2 h-2 bg-warning rounded-full animate-pulse"></div>
            <span class="text-sm font-semibold text-warning">Starting</span>
          </div>
          <span class="font-mono text-sm font-medium text-warning">{@version}</span>
          <.version_indicator sname={@sname} latest_release={@latest_release} version={@version} />
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

  defp version_indicator(assigns) do
    %Github{tag_name: tag_name, prerelease: prerelease} = assigns.latest_release
    current_version = assigns.version

    show_indicator =
      assigns.sname == "deployex" and
        tag_name != nil and
        tag_name != current_version and
        prerelease == false

    assigns =
      assigns
      |> assign(:show_indicator, show_indicator)
      |> assign(:new_release, tag_name)

    ~H"""
    <div :if={@show_indicator} class="inline-flex">
      <div
        class="btn btn-sm btn-circle bg-info/10 border-info/20 text-info hover:bg-info/20 hover:border-success/30 hover:scale-110 transition-all duration-200 flex-1 tooltip before:whitespace-pre-wrap"
        data-tip={"New version available #{@new_release}! \n Click to view releases"}
      >
        <a
          href="https://github.com/thiagoesteves/deployex/releases"
          target="_blank"
          rel="noopener noreferrer"
          class="flex items-center justify-center w-5 h-5 bg-info/20 border border-info/40 rounded-full hover:bg-info/30 hover:scale-110 transition-all duration-200 cursor-pointer"
        >
          <svg class="w-3 h-3 text-info" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M9 19l3 3m0 0l3-3m-3 3V10"
            >
            </path>
          </svg>
        </a>
      </div>
    </div>
    """
  end
end
