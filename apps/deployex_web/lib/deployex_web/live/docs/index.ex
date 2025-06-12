defmodule DeployexWeb.DocsLive do
  @moduledoc """
  """
  use DeployexWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} ui_settings={@ui_settings}>
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
