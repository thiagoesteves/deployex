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
    assert html =~ "Docs"

    html = index_live |> element("#toggle-nav-menu-button") |> render_click()

    refute html =~ "Applications"
    refute html =~ "Live Logs"
    refute html =~ "History Logs"
    refute html =~ "Observer Web"
    refute html =~ "Host Terminal"
    refute html =~ "Docs"

    html = index_live |> element("#toggle-nav-menu-button") |> render_click()

    assert html =~ "Applications"
    assert html =~ "Live Logs"
    assert html =~ "History Logs"
    assert html =~ "Observer Web"
    assert html =~ "Host Terminal"
    assert html =~ "Docs"
  end
end
