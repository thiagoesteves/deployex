defmodule DeployexWeb.Applications.WatcherTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias DeployexWeb.Fixture.Watcher, as: FixtureWatcher

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /applications Configuration button is available when pending changes are available",
       %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    refute liveview |> element("#deployex-config-changes") |> has_element?()

    send(liveview.pid, {:watcher_config_new, Node.self(), FixtureWatcher.build_pending_changes()})

    assert liveview |> element("#deployex-config-changes") |> has_element?()
    html = render(liveview)
    assert html =~ "5 configuration change(s) pending"
  end

  test "GET /applications Review pending changes and cancel", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    send(liveview.pid, {:watcher_config_new, Node.self(), FixtureWatcher.build_pending_changes()})

    assert liveview |> element("#deployex-config-changes") |> render_click()

    assert has_element?(liveview, "#yaml-config-changes-escape")
    assert has_element?(liveview, "#yaml-config-changes-cancel")
    assert has_element?(liveview, "#yaml-config-changes-apply")
  end
end
