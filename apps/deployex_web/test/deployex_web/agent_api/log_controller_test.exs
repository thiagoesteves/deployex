defmodule DeployexWeb.AgentApi.LogControllerTest do
  use DeployexWeb.AgentApiCase

  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias Sentinel.Logs.Message

  setup [:set_mox_global, :verify_on_exit!]

  setup %{conn: conn} do
    put_api_tokens(
      token_entry("ci", "read", "read-token") <>
        "," <> token_entry("bot", "operate", "operate-token")
    )

    retention = Application.get_env(:foundation, :logs_retention_time_ms)
    Application.put_env(:foundation, :logs_retention_time_ms, :timer.minutes(10))
    on_exit(fn -> Application.put_env(:foundation, :logs_retention_time_ms, retention) end)

    Deployer.StatusMock
    |> stub(:monitoring, fn -> {:ok, FixtureStatus.list()} end)

    Sentinel.LogsMock
    |> stub(:list_active_snames, fn ->
      ["deployex", "test_app-abc123", "test_app-old999", "other_app-abc123"]
    end)

    %{conn: bearer(conn, "read-token")}
  end

  defp unix_ms(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    DateTime.to_unix(at, :millisecond)
  end

  defp logs_path(params), do: "/v1/apps/test_app/logs?" <> URI.encode_query(params)

  defp stub_logs(messages) do
    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, _options ->
      messages
    end)
  end

  describe "GET /v1/apps/:name/logs" do
    test "returns one entry per line, oldest first", %{conn: conn} do
      expect(Sentinel.LogsMock, :list_data_by_sname_log_type, fn "test_app-abc123",
                                                                 "stderr",
                                                                 [from: 11] ->
        [
          %Message{timestamp: unix_ms("2026-10-23T12:00:00.123Z"), log: "first\r\nsecond\n"},
          %Message{timestamp: unix_ms("2026-10-23T12:00:01.000Z"), log: "third"}
        ]
      end)

      assert conn
             |> get("/v1/apps/test_app/logs?sname=test_app-abc123&type=stderr")
             |> json_response(200) == %{
               "logs" => [
                 %{"timestamp" => "2026-10-23T12:00:00.123Z", "line" => "first"},
                 %{"timestamp" => "2026-10-23T12:00:00.123Z", "line" => "second"},
                 %{"timestamp" => "2026-10-23T12:00:01.000Z", "line" => "third"}
               ],
               "truncated" => false
             }
    end

    test "returns the newest limit lines and says that it dropped older lines", %{conn: conn} do
      stub_logs([
        %Message{timestamp: unix_ms("2026-10-23T12:00:00Z"), log: "first\nsecond\n"},
        %Message{timestamp: unix_ms("2026-10-23T12:00:01Z"), log: "third"}
      ])

      for {limit, lines, truncated} <- [
            {"2", ["second", "third"], true},
            {"3", ["first", "second", "third"], false}
          ] do
        assert %{"logs" => logs, "truncated" => ^truncated} =
                 build_conn()
                 |> bearer("read-token")
                 |> get(
                   logs_path(%{
                     "sname" => "test_app-abc123",
                     "type" => "stdout",
                     "limit" => limit
                   })
                 )
                 |> json_response(200)

        assert Enum.map(logs, & &1["line"]) == lines
      end

      assert %{"logs" => [%{"line" => "third"}], "truncated" => true} =
               conn
               |> get(
                 logs_path(%{
                   "sname" => "test_app-abc123",
                   "type" => "stdout",
                   "since" => "2026-10-23T12:00:00Z",
                   "limit" => "1"
                 })
               )
               |> json_response(200)
    end

    test "returns at most 1000 lines without limit", %{conn: conn} do
      log = Enum.map_join(1..1001, "\n", &"line #{&1}")
      stub_logs([%Message{timestamp: unix_ms("2026-10-23T12:00:00Z"), log: log}])

      assert %{"logs" => logs, "truncated" => true} =
               conn
               |> get("/v1/apps/test_app/logs?sname=test_app-abc123&type=stdout")
               |> json_response(200)

      assert length(logs) == 1000
      assert hd(logs)["line"] == "line 2"
    end

    test "returns the lines at or after since", %{conn: conn} do
      stub_logs([
        %Message{timestamp: unix_ms("2026-10-23T12:00:00.499Z"), log: "before"},
        %Message{timestamp: unix_ms("2026-10-23T12:00:00.500Z"), log: "at"},
        %Message{timestamp: unix_ms("2026-10-23T12:00:00.501Z"), log: "after"}
      ])

      assert %{"logs" => logs} =
               conn
               |> get(
                 logs_path(%{
                   "sname" => "test_app-abc123",
                   "type" => "stdout",
                   "since" => "2026-10-23T14:00:00.500+02:00"
                 })
               )
               |> json_response(200)

      assert Enum.map(logs, & &1["line"]) == ["at", "after"]
    end

    test "reads only the minutes since since, and never past the retention", %{conn: conn} do
      since = DateTime.utc_now() |> DateTime.add(-5, :minute) |> DateTime.to_iso8601()

      expect(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, [from: from] ->
        assert from in 6..7
        []
      end)

      assert %{"logs" => []} =
               conn
               |> get(
                 logs_path(%{
                   "sname" => "test_app-abc123",
                   "type" => "stdout",
                   "since" => since
                 })
               )
               |> json_response(200)

      expect(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, [from: 11] ->
        []
      end)

      assert build_conn()
             |> bearer("read-token")
             |> get(
               logs_path(%{
                 "sname" => "test_app-abc123",
                 "type" => "stdout",
                 "since" => "2025-01-01T00:00:00Z"
               })
             )
             |> json_response(200)
    end

    test "returns the lines of an instance that no longer runs", %{conn: conn} do
      stub_logs([%Message{timestamp: unix_ms("2026-10-23T12:00:00Z"), log: "crashed"}])

      assert %{"logs" => [%{"line" => "crashed"}]} =
               conn
               |> get("/v1/apps/test_app/logs?sname=test_app-old999&type=stderr")
               |> json_response(200)
    end

    test "replaces bytes that are not UTF-8", %{conn: conn} do
      # tail can split a multibyte character between two chunks
      stub_logs([%Message{timestamp: unix_ms("2026-10-23T12:00:00Z"), log: "caf" <> <<0xC3>>}])

      assert %{"logs" => [%{"line" => "caf�"}]} =
               conn
               |> get("/v1/apps/test_app/logs?sname=test_app-abc123&type=stdout")
               |> json_response(200)
    end

    test "returns 404 for an sname that this app does not have", %{conn: conn} do
      for sname <- ["other_app-abc123", "test_app-nope00", "deployex"] do
        assert build_conn()
               |> bearer("read-token")
               |> get(logs_path(%{"sname" => sname, "type" => "stdout"}))
               |> json_response(404)
      end

      assert conn
             |> get("/v1/apps/deployex/logs?sname=deployex&type=stdout")
             |> json_response(404)
    end

    test "returns 404 for an unknown app and 503 before the first status update", %{conn: conn} do
      assert conn
             |> get("/v1/apps/unknown/logs?sname=unknown-abc123&type=stdout")
             |> json_response(404)

      stub(Deployer.StatusMock, :monitoring, fn -> {:ok, []} end)

      assert build_conn()
             |> bearer("read-token")
             |> get("/v1/apps/test_app/logs?sname=test_app-abc123&type=stdout")
             |> json_response(503)
    end

    test "returns 422 without sname or type, or for an unknown type", %{conn: conn} do
      assert conn |> get("/v1/apps/test_app/logs?type=stdout") |> json_response(422) ==
               %{"errors" => %{"detail" => "sname is required"}}

      for query <- ["sname=test_app-abc123", "sname=test_app-abc123&type=stdin"] do
        assert build_conn()
               |> bearer("read-token")
               |> get("/v1/apps/test_app/logs?" <> query)
               |> json_response(422) == %{
                 "errors" => %{"detail" => "type must be stdout or stderr"}
               }
      end

      assert build_conn()
             |> bearer("read-token")
             |> get("/v1/apps/test_app/logs?sname[]=test_app-abc123&type=stdout")
             |> json_response(422) == %{"errors" => %{"detail" => "sname is required"}}
    end

    test "returns 422 for a since that is not an ISO 8601 time with an offset" do
      for since <- ["yesterday", "2026-10-23T12:00:00", "1761220800000"] do
        assert %{"errors" => %{"detail" => "since must be an ISO 8601 time" <> _}} =
                 build_conn()
                 |> bearer("read-token")
                 |> get(
                   logs_path(%{
                     "sname" => "test_app-abc123",
                     "type" => "stdout",
                     "since" => since
                   })
                 )
                 |> json_response(422)
      end

      assert %{"errors" => %{"detail" => "since must be an ISO 8601 time" <> _}} =
               build_conn()
               |> bearer("read-token")
               |> get("/v1/apps/test_app/logs?sname=test_app-abc123&type=stdout&since[]=x")
               |> json_response(422)

      # An offset with a + that is not encoded reaches DeployEx as a space
      assert %{"errors" => %{"detail" => detail}} =
               build_conn()
               |> bearer("read-token")
               |> get(
                 "/v1/apps/test_app/logs?sname=test_app-abc123&type=stdout&since=2026-10-23T14:00:00+02:00"
               )
               |> json_response(422)

      assert detail =~ "write + as %2B"
    end

    test "returns 422 for a limit that is not an integer from 1 to 10000" do
      for limit <- ["0", "10001", "-1", "1.5", "ten", ""] do
        assert build_conn()
               |> bearer("read-token")
               |> get(
                 logs_path(%{"sname" => "test_app-abc123", "type" => "stdout", "limit" => limit})
               )
               |> json_response(422) == %{
                 "errors" => %{"detail" => "limit must be an integer from 1 to 10000"}
               }
      end

      assert %{"errors" => %{"detail" => "limit must be" <> _}} =
               build_conn()
               |> bearer("read-token")
               |> get("/v1/apps/test_app/logs?sname=test_app-abc123&type=stdout&limit[]=1")
               |> json_response(422)
    end

    test "needs a read token", %{conn: conn} do
      assert conn
             |> put_req_header("authorization", "Bearer operate-token")
             |> get("/v1/apps/test_app/logs?sname=test_app-abc123&type=stdout")
             |> json_response(403)
    end
  end
end
