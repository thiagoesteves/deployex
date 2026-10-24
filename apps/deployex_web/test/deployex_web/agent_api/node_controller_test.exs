defmodule DeployexWeb.AgentApi.NodeControllerTest do
  use DeployexWeb.AgentApiCase, async: false

  import Mock
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [:set_mox_global, :verify_on_exit!]

  setup %{conn: conn} do
    put_api_tokens(token_entry("ci", "read", "read-token"))
    %{conn: bearer(conn, "read-token")}
  end

  test "GET /v1/node returns DeployEx and the host", %{conn: conn} do
    deployex =
      FixtureStatus.deployex(%{node: :deployex@host, otp_version: "29", elixir_version: "1.20.4"})

    stub(Deployer.StatusMock, :monitoring, fn ->
      {:ok, [deployex, FixtureStatus.application()]}
    end)

    host_info = %Host.Info{
      host: "Linux",
      description: "Ubuntu 24.04",
      uptime: "15 days",
      uptime_seconds: 1_296_000,
      cpu: 50.0,
      cpus: 2,
      memory_total: 2_000,
      memory_free: 500
    }

    with_mock Host.Info, latest: fn -> host_info end do
      assert conn |> get("/v1/node") |> json_response(200) == %{
               "node" => "deployex@host",
               "version" => "1.2.3",
               "started_at" => "2026-10-01T07:00:00Z",
               "otp_version" => "29",
               "elixir_version" => "1.20.4",
               "host" => %{
                 "os" => "Linux",
                 "description" => "Ubuntu 24.04",
                 "uptime_seconds" => 1_296_000,
                 "cpus" => 2,
                 "cpu_percent" => 25.0,
                 "memory_total" => 2_000,
                 "memory_free" => 500
               }
             }
    end
  end

  test "GET /v1/node returns no host before the first reading", %{conn: conn} do
    stub(Deployer.StatusMock, :monitoring, fn -> {:ok, FixtureStatus.list()} end)

    with_mock Host.Info, latest: fn -> nil end do
      assert %{"host" => nil, "version" => "1.2.3"} =
               conn |> get("/v1/node") |> json_response(200)
    end
  end

  test "GET /v1/node returns no cpu percent when the host reading has none", %{conn: conn} do
    stub(Deployer.StatusMock, :monitoring, fn -> {:ok, FixtureStatus.list()} end)

    with_mock Host.Info, latest: fn -> %Host.Info{host: "Windows"} end do
      assert %{"host" => %{"os" => "Windows", "cpu_percent" => nil}} =
               conn |> get("/v1/node") |> json_response(200)
    end
  end

  test "GET /v1/node returns 503 when the status server does not answer", %{conn: conn} do
    stub(Deployer.StatusMock, :monitoring, fn -> {:error, :rescued} end)

    assert conn |> get("/v1/node") |> json_response(503)
  end
end
