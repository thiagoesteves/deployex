defmodule DeployexWeb.ObserverLive do
  @moduledoc """
  """
  use DeployexWeb, :live_view

  alias DeployexWeb.Components.SystemBar

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_path={@current_path}
      current_user={@current_user}
      host_info={@host_info}
    >
      <div class="min-h-screen bg-base-300">
        <!-- Header -->
        <div class="bg-base-100 border-b border-base-200 shadow-sm">
          <SystemBar.content info={@host_info} />
        </div>
        <!-- Main Content -->
        <div class="max-w-8xl mx-auto px-3 py-3">
          <!-- Observer Card -->
          <div class="card bg-base-100 shadow-lg border border-base-200">
            <div class="card-body p-0">
              <!-- Observer Frame -->
              <div class="relative">
                <iframe
                  src={~p"/observer/tracing?iframe=true"}
                  class="w-full min-h-[90vh] border-0"
                  title="Observer Web"
                ></iframe>
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
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :current_path, "/embedded-observer")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Observer Web")
  end
end
