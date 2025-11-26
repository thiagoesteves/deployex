defmodule DeployexWeb.Docs.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup [
    :log_in_default_user
  ]

  test "GET /documentation", %{conn: conn} do
    {:ok, index_live, html} = live(conn, ~p"/documentation")

    assert html =~ "Deployex Docs"

    # Trigger handle_params by navigating
    assert index_live
           |> element("iframe")
           |> has_element?()
  end
end
