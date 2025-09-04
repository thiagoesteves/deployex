defmodule DeployexWeb.NavMenuTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Cache
  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /applications", %{conn: conn} do
    Cache.UiSettings.set(%Cache.UiSettings{})

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, index_live, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "Applications"
    assert html =~ "Live Logs"
    assert html =~ "History Logs"
    assert html =~ "Observer Web"
    assert html =~ "Host Terminal"
    assert html =~ "Documentation"

    # Test collapse functionality - in collapsed state, text labels are hidden
    html = index_live |> element("#toggle-nav-menu-button") |> render_click()

    # In collapsed state, navigation items should still be present but text labels hidden
    assert html =~ "aria-label=\"Applications\""
    assert html =~ "aria-label=\"Live Logs\""
    assert html =~ "aria-label=\"Documentation\""

    # But the text labels themselves should not be visible
    refute html =~ ">Applications<"
    refute html =~ ">Live Logs<"
    refute html =~ ">Documentation<"

    # Test expand functionality - text labels should be visible again
    html = index_live |> element("#toggle-nav-menu-button") |> render_click()

    assert html =~ "Applications"
    assert html =~ "Live Logs"
    assert html =~ "History Logs"
    assert html =~ "Observer Web"
    assert html =~ "Host Terminal"
    assert html =~ "Documentation"
  end
end
