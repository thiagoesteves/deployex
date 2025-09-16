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

    assert html =~ "style=\"width: 16rem;\""
    refute html =~ "style=\"width: 5rem;\""

    # Test collapse functionality - in collapsed state, text labels are hidden
    html = index_live |> element("#toggle-nav-menu-button") |> render_click()

    # In collapsed state, navigation items should still be present but text labels hidden
    assert html =~ "aria-label=\"Applications\""
    assert html =~ "aria-label=\"Live Logs\""
    assert html =~ "aria-label=\"Documentation\""

    # Check the width of the nav menu column
    refute html =~ "style=\"width: 16rem;\""
    assert html =~ "style=\"width: 5rem;\""

    # Test expand functionality - text labels should be visible again
    html = index_live |> element("#toggle-nav-menu-button") |> render_click()

    assert html =~ "style=\"width: 16rem;\""
    refute html =~ "style=\"width: 5rem;\""

    assert html =~ "Applications"
    assert html =~ "Live Logs"
    assert html =~ "History Logs"
    assert html =~ "Observer Web"
    assert html =~ "Host Terminal"
    assert html =~ "Documentation"
  end
end
