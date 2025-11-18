defmodule DeployexWeb.Applications.WatcherTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias Sentinel.Fixture.Watcher, as: FixtureWatcher

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
    assert html =~ "4 configuration change(s) pending"
  end

  test "GET /applications Review pending changes and click cancel button", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    send(liveview.pid, {:watcher_config_new, Node.self(), FixtureWatcher.build_pending_changes()})

    assert liveview |> element("#deployex-config-changes") |> render_click()

    assert has_element?(liveview, "#yaml-config-changes-cancel")
    assert has_element?(liveview, "#yaml-config-changes-apply")

    assert liveview |> element("#yaml-config-changes-cancel") |> render_click()

    assert liveview |> element("#deployex-config-changes") |> has_element?()
    html = render(liveview)
    assert html =~ "4 configuration change(s) pending"
  end

  test "GET /applications Review pending changes and click escape button", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    send(liveview.pid, {:watcher_config_new, Node.self(), FixtureWatcher.build_pending_changes()})

    assert liveview |> element("#deployex-config-changes") |> render_click()

    assert has_element?(liveview, "#yaml-config-changes-escape")
    assert has_element?(liveview, "#yaml-config-changes-apply")

    assert liveview |> element("#yaml-config-changes-escape") |> render_click()

    assert liveview |> element("#deployex-config-changes") |> has_element?()
    html = render(liveview)
    assert html =~ "4 configuration change(s) pending"
  end

  test "GET /applications Review pending changes and apply changes", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    send(liveview.pid, {:watcher_config_new, Node.self(), FixtureWatcher.build_pending_changes()})

    assert liveview |> element("#deployex-config-changes") |> render_click()

    assert has_element?(liveview, "#yaml-config-changes-escape")
    assert has_element?(liveview, "#yaml-config-changes-apply")

    assert liveview |> element("#yaml-config-changes-apply") |> render_click()

    send(liveview.pid, {:watcher_config_new, Node.self(), nil})

    refute liveview |> element("#deployex-config-changes") |> has_element?()
  end

  test "GET /applications ignore changes from other nodes", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    send(
      liveview.pid,
      {:watcher_config_new, :"another@node.host", FixtureWatcher.build_pending_changes()}
    )

    refute liveview |> element("#deployex-config-changes") |> has_element?()
  end
end
