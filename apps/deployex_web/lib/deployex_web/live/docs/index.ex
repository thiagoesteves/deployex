defmodule DeployexWeb.DocsLive do
  @moduledoc """
  The documentation that ships with DeployEx, in a frame inside the shell. `page` in the query opens one
  page of it, like `guide-yaml.html`.
  """
  use DeployexWeb, :live_view

  # A page of the docs folder, with an optional anchor. Anything else opens the index
  @page ~r/\A[A-Za-z0-9._-]+\.html(#[A-Za-z0-9_-]+)?\z/

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, current_path: "/documentation", page_title: "Documentation")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page =
      if is_binary(params["page"]) and Regex.match?(@page, params["page"]),
        do: params["page"],
        else: "index.html"

    {:noreply, assign(socket, :page, page)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_path={@current_path}
      current_user={@current_user}
      host_info={@host_info}
      recent_events={@recent_events}
      socket={@socket}
    >
      <div>
        <iframe
          src={"/docs/#{@page}"}
          class="min-h-screen"
          width="100%"
          height="100%"
          title="DeployEx documentation"
        ></iframe>
      </div>
    </Layouts.app>
    """
  end
end
