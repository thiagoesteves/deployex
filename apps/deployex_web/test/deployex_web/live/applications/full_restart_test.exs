defmodule DeployexWeb.Applications.FullRestartTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
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

    assert index_live |> element("#app-full-restart-test-app") |> render_click() =~
             "All running application instances will be terminated"

    assert index_live |> element("#cancel-button-full-restart-cancel", "Cancel") |> render_click()

    refute has_element?(index_live, "#cancel-button-full-restart-cancel")
  end

  test "Click restart Button, confirm the operation - applications", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-full-restart-test-app") |> render_click() =~
             "All running application instances will be terminated"

    assert index_live
           |> element("#danger-button-full-restart-execute", "Yes, Restart All")
           |> render_click()

    refute has_element?(index_live, "#cancel-button-full-restart-cancel")
  end
end
