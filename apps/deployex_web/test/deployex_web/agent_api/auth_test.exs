defmodule DeployexWeb.AgentApi.AuthTest do
  use DeployexWeb.AgentApiCase

  import Mox

  alias DeployexWeb.AgentApi.Auth
  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [:set_mox_global, :verify_on_exit!]

  setup do
    put_api_tokens(token_entry("ci", "read", "read-token"))

    Deployer.StatusMock
    |> stub(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> stub(:ghosted_version_list, fn _name -> [] end)

    :ok
  end

  test "refuses a request with no token", %{conn: conn} do
    conn = get(conn, "/v1/apps")

    assert json_response(conn, 401) == %{"errors" => %{"detail" => "Unauthorized"}}
    assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
  end

  test "refuses a wrong token", %{conn: conn} do
    conn = conn |> bearer("wrong-token") |> get("/v1/apps")

    assert json_response(conn, 401) == %{"errors" => %{"detail" => "Unauthorized"}}
  end

  test "refuses a header that is not a bearer token", %{conn: conn} do
    conn = conn |> put_req_header("authorization", "Basic read-token") |> get("/v1/apps")

    assert json_response(conn, 401)
  end

  test "lets a read token through, with the scheme in any case", %{conn: conn} do
    conn = conn |> put_req_header("authorization", "bearer read-token") |> get("/v1/apps")

    assert %{"apps" => [_app]} = json_response(conn, 200)
    assert conn.assigns.api_token_name == "ci"
  end

  test "refuses a token without the scope of the route", %{conn: conn} do
    conn = conn |> bearer("read-token") |> Auth.call("operate")

    assert conn.halted
    assert json_response(conn, 403) == %{"errors" => %{"detail" => "Forbidden"}}
  end

  test "init/1 needs a scope" do
    assert Auth.init(scope: "read") == "read"
    assert_raise KeyError, fn -> Auth.init([]) end
  end
end
