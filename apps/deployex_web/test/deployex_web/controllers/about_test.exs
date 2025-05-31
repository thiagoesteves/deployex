defmodule DeployexWeb.PageControllerTest do
  use DeployexWeb.ConnCase

  import Mox
  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  test "GET / redirect to /users/log_in if not authenticated", %{conn: conn} do
    Deployer.StatusMock
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    conn = get(conn, ~p"/")

    assert html_response(conn, 302) =~ "You are being <a href=\"/users/log_in\">redirected</a>."
  end

  describe "" do
    setup :log_in_default_user

    test "GET / redirect to /applications if authenticated", %{conn: conn} do
      Deployer.StatusMock
      |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

      conn = get(conn, ~p"/")

      assert html_response(conn, 200) =~ "Monitoring Elixir Apps"
    end
  end

  test "GET /about", %{conn: conn} do
    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "DeployEx is a lightweight tool designed"
  end
end
