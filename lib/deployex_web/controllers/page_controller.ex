defmodule DeployexWeb.PageController do
  use DeployexWeb, :controller

  def home(conn, _params) do
    # redirect to the default page, e. g., home or login
    conn
    |> redirect(to: ~p"/applications")
  end

  def about(conn, _params) do
    render(conn, :about)
  end
end
