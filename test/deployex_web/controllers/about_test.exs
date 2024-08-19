defmodule DeployexWeb.PageControllerTest do
  use DeployexWeb.ConnCase

  test "GET / redirect to /applications", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "Monitoring Elixir Apps"
  end

  test "GET /about", %{conn: conn} do
    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "Deployex is a lightweight tool designed"
  end
end
