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

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus

  test "Click restart Button, but cancel the operation - instance 1", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-1") |> render_click() =~
             "Are you sure you want to restart instance 1?"

    assert index_live |> element("#cancel-button-1", "Cancel") |> render_click()

    refute has_element?(index_live, "#cancel-button-1")
  end

  test "Click restart Button, confirm the operation - instance 1", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.MonitorMock
    |> expect(:restart, 1, fn 1 -> :ok end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-1") |> render_click() =~
             "Are you sure you want to restart instance 1?"

    assert index_live |> element("#confirm-button-1", "Confirm") |> render_click()

    refute has_element?(index_live, "#cancel-button-1")
  end

  test "Click restart Button, but cancel the operation - deployex", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-0") |> render_click() =~
             "Are you sure you want to restart deployex?"

    assert index_live |> element("#cancel-button-0", "Cancel") |> render_click()

    refute has_element?(index_live, "#cancel-button-0")
  end

  test "Click restart Button, confirm the operation - deployex", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options -> :ok end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-0") |> render_click() =~
             "Are you sure you want to restart deployex?"

    assert capture_log(fn ->
             assert index_live |> element("#confirm-button-0", "Confirm") |> render_click()
           end) =~ "Deployex was requested to terminate, see you soon!!!"

    refute has_element?(index_live, "#cancel-button-0")
  end
end
