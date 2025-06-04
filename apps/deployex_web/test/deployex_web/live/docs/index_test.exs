defmodule DeployexWeb.Terminal.DocsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup [
    :log_in_default_user
  ]

  test "GET /docs", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/applications/deployex/docs")

    assert html =~ "Deployex Docs"
  end
end
