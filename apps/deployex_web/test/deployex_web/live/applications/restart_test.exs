defmodule DeployexWeb.Applications.RestartTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import Mox

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  test "Click restart Button, but cancel the operation - applications", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-test-app-abc123") |> render_click() =~
             "Are you sure you want to restart <span class=\"font-semibold text-primary\">test_app-abc123</span>?\n      </p><div class=\"text-base-content/60 leading-relaxed\">\n        The application will be stopped and restarted automatically."

    assert index_live |> element("#cancel-button-test-app-abc123", "Cancel") |> render_click()

    refute has_element?(index_live, "#cancel-button-test-app-abc123")
  end

  test "Click restart Button, confirm the operation - applications", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    Deployer.MonitorMock
    |> expect(:restart, 1, fn _sname -> :ok end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-test-app-abc123") |> render_click() =~
             "Are you sure you want to restart <span class=\"font-semibold text-primary\">test_app-abc123</span>?\n      </p><div class=\"text-base-content/60 leading-relaxed\">\n        The application will be stopped and restarted automatically."

    assert index_live
           |> element("#confirm-button-test-app-abc123", "Restart App")
           |> render_click()

    refute has_element?(index_live, "#cancel-button-test-app-abc123")
  end

  test "Click restart Button, but cancel the operation - deployex", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-deployex") |> render_click() =~
             "Are you sure you want to restart <span class=\"font-semibold text-red-600\">deployex</span>?\n        All running applications will be affected."

    assert index_live |> element("#cancel-button-deployex", "Cancel") |> render_click()

    refute has_element?(index_live, "#cancel-button-deployex")
  end

  test "Click restart Button, confirm the operation - deployex", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options -> :ok end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-deployex") |> render_click() =~
             "Are you sure you want to restart <span class=\"font-semibold text-red-600\">deployex</span>?\n        All running applications will be affected."

    assert capture_log(fn ->
             assert index_live
                    |> element("#danger-button-deployex", "Terminate All Apps")
                    |> render_click()
           end) =~ "Deployex was requested to terminate, see you soon!!!"

    refute has_element?(index_live, "#cancel-button-deployex")
  end
end
