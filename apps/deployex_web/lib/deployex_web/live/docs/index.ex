defmodule DeployexWeb.DocsLive do
  @moduledoc """
  """
  use DeployexWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :current_path, "/applications/deployex/docs")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} ui_settings={@ui_settings} current_path={@current_path}>
      <div>
        <iframe
          src={~p"/docs/index.html"}
          class="min-h-screen"
          width="100%"
          height="100%"
          title="Deployex Docs"
        >
        </iframe>
      </div>
    </Layouts.app>
    """
  end
end
