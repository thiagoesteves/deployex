defmodule DeployexWeb.AgentApi.AppControllerTest do
  use DeployexWeb.AgentApiCase

  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [:set_mox_global, :verify_on_exit!]

  setup %{conn: conn} do
    put_api_tokens(token_entry("ci", "read", "read-token"))
    %{conn: bearer(conn, "read-token")}
  end

  defp stub_status(monitoring \\ {:ok, FixtureStatus.list()}) do
    Deployer.StatusMock
    |> stub(:monitoring, fn -> monitoring end)
    |> stub(:ghosted_version_list, fn "test_app" ->
      [FixtureStatus.version(%{version: "4.5.7"})]
    end)
    |> stub(:history_version_list, fn "test_app", [] ->
      [FixtureStatus.version(%{version: "4.5.6", pre_commands: ["eval Secret.run()"]})]
    end)
  end

  describe "GET /v1/apps" do
    test "lists each monitored app, without DeployEx", %{conn: conn} do
      stub_status()

      assert %{"apps" => [app]} = conn |> get("/v1/apps") |> json_response(200)

      assert %{
               "name" => "test_app",
               "language" => "elixir",
               "replicas" => 1,
               "mode" => "automatic",
               "manual_version" => nil,
               "ghosted_versions" => ["4.5.7"],
               "instances" => [instance]
             } = app

      assert instance == %{
               "sname" => "test_app-abc123",
               "node" =>
                 "test_app-abc123@" <>
                   (node() |> Atom.to_string() |> String.split("@") |> List.last()),
               "version" => "4.5.6",
               "status" => "running",
               "otp" => "connected",
               "last_deployment" => "full_deployment",
               "crash_restart_count" => 0,
               "force_restart_count" => 0,
               "uptime" => "long time",
               "ports" => [%{"key" => "PORT", "port" => 5678}]
             }
    end

    test "returns 503 when the status server does not answer", %{conn: conn} do
      stub_status({:error, :rescued})

      assert conn |> get("/v1/apps") |> json_response(503) ==
               %{"errors" => %{"detail" => "Service Unavailable"}}
    end

    test "returns 503 before the first status update, not an empty list or a 404", %{conn: conn} do
      stub_status({:ok, []})

      assert conn |> get("/v1/apps") |> json_response(503)

      assert build_conn()
             |> bearer("read-token")
             |> get("/v1/apps/test_app")
             |> json_response(503)
    end
  end

  describe "GET /v1/apps/:name" do
    test "returns one app with the manual version", %{conn: conn} do
      config = %{mode: :manual, manual_version: FixtureStatus.version(%{version: "4.5.5"})}

      stub_status({:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{}, config)]})

      assert %{"name" => "test_app", "mode" => "manual", "manual_version" => "4.5.5"} =
               conn |> get("/v1/apps/test_app") |> json_response(200)
    end

    test "returns 404 for an app that this host does not monitor", %{conn: conn} do
      stub_status()

      assert conn |> get("/v1/apps/unknown") |> json_response(404) ==
               %{"errors" => %{"detail" => "Not Found"}}
    end

    test "does not return DeployEx as an app", %{conn: conn} do
      stub_status()

      assert conn |> get("/v1/apps/deployex") |> json_response(404)
    end
  end

  describe "GET /v1/apps/:name/versions" do
    test "returns the version history, without the pre_commands", %{conn: conn} do
      stub_status()

      assert %{"versions" => [version]} =
               conn |> get("/v1/apps/test_app/versions") |> json_response(200)

      assert %{
               "version" => "4.5.6",
               "hash" => "local",
               "sname" => "testapp-abc123",
               "deployment" => "full_deployment",
               "inserted_at" => _inserted_at
             } = version

      refute Map.has_key?(version, "pre_commands")
    end

    test "returns 404 before any catalog read for an unknown name", %{conn: conn} do
      stub_status()

      assert conn |> get("/v1/apps/..%2F..%2Fetc/versions") |> json_response(404)
    end
  end

  describe "GET /v1/apps/:name/ghosted" do
    test "returns the ghosted versions", %{conn: conn} do
      stub_status()

      assert %{"ghosted_versions" => [%{"version" => "4.5.7"}]} =
               conn |> get("/v1/apps/test_app/ghosted") |> json_response(200)
    end

    test "returns 404 for an unknown app", %{conn: conn} do
      stub_status()

      assert conn |> get("/v1/apps/unknown/ghosted") |> json_response(404)
    end

    test "lists the newest ghosted version first, as the app snapshot does", %{conn: conn} do
      older = FixtureStatus.version(%{version: "4.5.7", inserted_at: ~N[2026-10-01 10:00:00]})
      newer = FixtureStatus.version(%{version: "4.5.8", inserted_at: ~N[2026-10-02 10:00:00]})
      no_time = FixtureStatus.version(%{version: "4.5.1", inserted_at: nil})

      stub_status()

      stub(Deployer.StatusMock, :ghosted_version_list, fn "test_app" ->
        [older, no_time, newer]
      end)

      assert %{"ghosted_versions" => ghosted} =
               conn |> get("/v1/apps/test_app/ghosted") |> json_response(200)

      assert Enum.map(ghosted, & &1["version"]) == ["4.5.8", "4.5.7", "4.5.1"]

      assert %{"ghosted_versions" => ["4.5.8", "4.5.7", "4.5.1"]} =
               build_conn()
               |> bearer("read-token")
               |> get("/v1/apps/test_app")
               |> json_response(200)
    end
  end

  test "returns 404 for an unknown route", %{conn: conn} do
    assert conn |> get("/v1/unknown") |> json_response(404)
  end
end
