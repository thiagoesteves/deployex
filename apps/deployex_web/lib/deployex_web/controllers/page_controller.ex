defmodule DeployexWeb.PageController do
  use DeployexWeb, :controller

  def show(conn, _params) do
    render(conn, :about)
  end
end
