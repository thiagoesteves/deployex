defmodule DeployexWeb.ComingSoonLive do
  use DeployexWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-700 flex flex-col items-center justify-center">
      <h1 class="text-5xl text-white font-bold mb-8 animate-pulse">
        Coming Soon
      </h1>
      <p class="text-white text-lg mb-8">
        We're working hard to bring you something amazing. Stay tuned!
      </p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
