defmodule DeployexWeb.Applications.AppTabTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "Select applications",
       %{
         conn: conn
       } do
    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application()]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Deployex"

    refute html =~ "phx-value-name=\"test_app\" class=\"tab tab-lg tab-active\""

    assert view |> element("#tab-application-test_app") |> render_click() =~
             "phx-value-name=\"test_app\" class=\"tab tab-lg tab-active\""

    assert view |> element("#tab-application-test_app-abc123") |> render_click() =~
             "phx-value-name=\"test_app\" class=\"tab tab-lg tab-active\""
  end
end
