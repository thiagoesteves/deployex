defmodule DeployexWeb.ObserverLive do
  @moduledoc """
  """
  use DeployexWeb, :live_view

  alias DeployexWeb.Cache.UiSettings
  alias DeployexWeb.Components.SystemBar

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} ui_settings={@ui_settings} current_path={@current_path}>
      <div class="min-h-screen bg-base-300">
        
    <!-- Header -->
        <div class="bg-base-100 border-b border-base-200 shadow-sm">
          <div class="max-w-7xl mx-auto px-6 py-6">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-3xl font-bold text-base-content">System Observer</h1>
                <p class="text-base-content/60 mt-1">
                  Real-time system monitoring and debugging tools
                </p>
              </div>
              <div class="flex items-center gap-4">
                <!-- Status Badge -->
                <div class="badge badge-success gap-2">
                  <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fill-rule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                      clip-rule="evenodd"
                    >
                    </path>
                  </svg>
                  Observer Active
                </div>
              </div>
            </div>
          </div>
          <SystemBar.content info={@host_info} />
        </div>
        
    <!-- Main Content -->
        <div class="max-w-7xl mx-auto px-6 py-6">
          <!-- Observer Card -->
          <div class="card bg-base-100 shadow-lg border border-base-200">
            <div class="card-body p-0">
              <!-- Card Header -->
              <div class="px-6 py-4 border-b border-base-200 bg-gradient-to-r from-base-100 to-base-200/30">
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
                    <svg
                      class="w-6 h-6 text-primary"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                      >
                      </path>
                    </svg>
                  </div>
                  <div>
                    <h2 class="text-lg font-bold text-base-content">Observer Web Interface</h2>
                    <p class="text-sm text-base-content/60">
                      Interactive system monitoring dashboard
                    </p>
                  </div>
                </div>
              </div>
              
    <!-- Observer Frame -->
              <div class="relative">
                <iframe
                  src={~p"/observer/tracing?iframe=true"}
                  class="w-full h-[calc(100vh-280px)] border-0"
                  title="Observer Web"
                  style="min-height: 600px;"
                >
                </iframe>
                
    <!-- Loading Overlay (optional) -->
                <div
                  class="absolute inset-0 bg-base-100/80 flex items-center justify-center opacity-0 pointer-events-none transition-opacity duration-300"
                  id="observer-loading"
                >
                  <div class="flex flex-col items-center gap-4">
                    <span class="loading loading-spinner loading-lg text-primary"></span>
                    <p class="text-base-content/60">Loading Observer...</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
          
    <!-- Info Cards -->
          <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mt-6">
            <div class="card bg-base-100 shadow-sm border border-base-200">
              <div class="card-body p-6">
                <div class="flex items-center gap-3">
                  <div class="w-8 h-8 rounded-lg bg-info/10 flex items-center justify-center">
                    <svg
                      class="w-5 h-5 text-info"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                      >
                      </path>
                    </svg>
                  </div>
                  <div>
                    <h3 class="font-semibold text-base-content">System Monitoring</h3>
                    <p class="text-sm text-base-content/60">Real-time process and memory tracking</p>
                  </div>
                </div>
              </div>
            </div>

            <div class="card bg-base-100 shadow-sm border border-base-200">
              <div class="card-body p-6">
                <div class="flex items-center gap-3">
                  <div class="w-8 h-8 rounded-lg bg-warning/10 flex items-center justify-center">
                    <svg
                      class="w-5 h-5 text-warning"
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
                  </div>
                  <div>
                    <h3 class="font-semibold text-base-content">Performance Analysis</h3>
                    <p class="text-sm text-base-content/60">CPU usage and bottleneck detection</p>
                  </div>
                </div>
              </div>
            </div>

            <div class="card bg-base-100 shadow-sm border border-base-200">
              <div class="card-body p-6">
                <div class="flex items-center gap-3">
                  <div class="w-8 h-8 rounded-lg bg-success/10 flex items-center justify-center">
                    <svg
                      class="w-5 h-5 text-success"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                      >
                      </path>
                    </svg>
                  </div>
                  <div>
                    <h3 class="font-semibold text-base-content">Debug Tools</h3>
                    <p class="text-sm text-base-content/60">Interactive debugging and tracing</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    # Subscribe to receive System info
    Host.Memory.subscribe()

    {:ok,
     socket
     |> assign(:host_info, nil)
     |> assign(:current_path, "/embedded-observer")}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:host_info, nil)
     |> assign(:current_path, "/embedded-observer")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Observer Web")
  end

  @impl true
  def handle_info({:update_system_info, host_info}, socket) do
    # Sync ui_settings from cache to ensure NavMenu has latest state
    ui_settings = UiSettings.get()

    {:noreply,
     socket
     |> assign(:host_info, host_info)
     |> assign(:ui_settings, ui_settings)}
  end
end
