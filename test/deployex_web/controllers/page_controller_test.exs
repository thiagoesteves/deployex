defmodule DeployexWeb.PageControllerTest do
  use DeployexWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "Coming Soon"
  end
end
