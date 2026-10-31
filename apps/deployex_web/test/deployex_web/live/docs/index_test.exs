defmodule DeployexWeb.Docs.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup [:log_in_default_user]

  @tag :capture_log
  test "GET /documentation opens the docs index in a frame", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/documentation")

    assert html =~ ~s(title="DeployEx documentation")
    assert html =~ ~s(src="/docs/index.html")
  end

  @tag :capture_log
  test "page opens one page of the docs, with its anchor", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/documentation?page=guide-yaml.html")
    assert html =~ ~s(src="/docs/guide-yaml.html")

    {:ok, _view, html} = live(conn, "/documentation?page=guide-yaml.html%23applications")
    assert html =~ ~s(src="/docs/guide-yaml.html#applications")
  end

  @tag :capture_log
  test "page opens the index for anything that is not a docs page", %{conn: conn} do
    for page <- [
          "https://example.com/x.html",
          "../../etc/passwd",
          "a/b.html",
          "javascript:alert(1)"
        ] do
      {:ok, _view, html} = live(conn, ~p"/documentation?#{%{page: page}}")
      assert html =~ ~s(src="/docs/index.html")
    end
  end
end
