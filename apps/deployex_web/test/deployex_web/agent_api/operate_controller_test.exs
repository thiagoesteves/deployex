defmodule DeployexWeb.AgentApi.OperateControllerTest do
  use DeployexWeb.AgentApiCase

  import ExUnit.CaptureLog
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [:set_mox_global, :verify_on_exit!]

  setup %{conn: conn} do
    put_api_tokens(
      Enum.join(
        [
          token_entry("ops", "read+operate", "operate-token"),
          token_entry("ci", "read", "read-token"),
          token_entry("bot", "operate", "operate-only-token")
        ],
        ","
      )
    )

    Deployer.StatusMock
    |> stub(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> stub(:history_version_list, fn "test_app", [] ->
      [FixtureStatus.version(%{version: "4.5.6"})]
    end)

    %{conn: bearer(conn, "operate-token")}
  end

  defp stub_ghosted(versions) do
    {:ok, ghosted} = Agent.start_link(fn -> versions end)

    Deployer.StatusMock
    |> stub(:ghosted_version_list, fn "test_app" ->
      ghosted |> Agent.get(& &1) |> Enum.map(&FixtureStatus.version(%{version: &1}))
    end)

    ghosted
  end

  describe "POST /v1/apps/:name/restart" do
    test "restarts the app as the dashboard button does, and writes the audit line", %{conn: conn} do
      Process.register(self(), :test_app)

      log =
        capture_log(fn ->
          assert conn |> post("/v1/apps/test_app/restart") |> json_response(202) == %{
                   "name" => "test_app",
                   "restart" => "accepted"
                 }
        end)

      assert_receive {:"$gen_cast", :restart_deployments}

      assert log =~
               ~s(Agent API operate: token=ops from=127.0.0.1 action=restart app="test_app" result=ok)
    end

    test "gives 404 for an app that the host does not monitor", %{conn: conn} do
      Process.register(self(), :unknown)

      log =
        capture_log(fn ->
          assert conn |> post("/v1/apps/unknown/restart") |> json_response(404)
        end)

      refute_received {:"$gen_cast", :restart_deployments}
      assert log =~ ~s(action=restart app="unknown" result=not_found)
    end
  end

  describe "DELETE /v1/apps/:name/ghosted/:version" do
    test "removes one ghosted version and returns the rest", %{conn: conn} do
      ghosted = stub_ghosted(["4.5.7", "4.5.8"])

      Deployer.StatusMock
      |> expect(:remove_ghosted_version, fn "test_app", "4.5.7" ->
        Agent.update(ghosted, &List.delete(&1, "4.5.7"))
        {:ok, []}
      end)

      log =
        capture_log(fn ->
          assert %{"ghosted_versions" => [%{"version" => "4.5.8"}]} =
                   conn |> delete("/v1/apps/test_app/ghosted/4.5.7") |> json_response(200)
        end)

      assert log =~ ~s(action=remove_ghosted app="test_app" version="4.5.7" result=ok)
    end

    test "gives 404 for a version that is not ghosted", %{conn: conn} do
      stub_ghosted(["4.5.7"])

      Deployer.StatusMock
      |> expect(:remove_ghosted_version, 0, fn _name, _version -> {:ok, []} end)

      log =
        capture_log(fn ->
          assert conn |> delete("/v1/apps/test_app/ghosted/9.9.9") |> json_response(404)
        end)

      assert log =~ ~s(version="9.9.9" result=not_found)
    end
  end

  describe "DELETE /v1/apps/:name/ghosted" do
    test "clears every ghosted version", %{conn: conn} do
      ghosted = stub_ghosted(["4.5.7", "4.5.8"])

      Deployer.StatusMock
      |> expect(:clear_ghosted_versions, fn "test_app" ->
        Agent.update(ghosted, fn _versions -> [] end)
        {:ok, []}
      end)

      log =
        capture_log(fn ->
          assert conn |> delete("/v1/apps/test_app/ghosted") |> json_response(200) == %{
                   "ghosted_versions" => []
                 }
        end)

      assert log =~ ~s(action=clear_ghosted app="test_app" result=ok)
    end
  end

  describe "PUT /v1/apps/:name/mode" do
    test "sets the automatic mode", %{conn: conn} do
      Deployer.StatusMock
      |> expect(:set_mode, fn "test_app", :automatic, "" -> {:ok, %{}} end)

      log =
        capture_log(fn ->
          assert conn
                 |> put("/v1/apps/test_app/mode", %{"mode" => "automatic"})
                 |> json_response(200) == %{
                   "name" => "test_app",
                   "mode" => "automatic",
                   "manual_version" => nil
                 }
        end)

      assert log =~ ~s(action=set_mode app="test_app" mode="automatic" result=ok)
    end

    test "pins a version from the history", %{conn: conn} do
      Deployer.StatusMock
      |> expect(:set_mode, fn "test_app", :manual, "4.5.6" -> {:ok, %{}} end)

      assert conn
             |> put("/v1/apps/test_app/mode", %{"mode" => "manual", "version" => "4.5.6"})
             |> json_response(200) == %{
               "name" => "test_app",
               "mode" => "manual",
               "manual_version" => "4.5.6"
             }
    end

    test "refuses a version that is not in the history", %{conn: conn} do
      Deployer.StatusMock |> expect(:set_mode, 0, fn _name, _mode, _version -> {:ok, %{}} end)

      log =
        capture_log(fn ->
          assert conn
                 |> put("/v1/apps/test_app/mode", %{"mode" => "manual", "version" => "9.9.9"})
                 |> json_response(422) == %{
                   "errors" => %{
                     "detail" => ~s(version "9.9.9" is not in the history of test_app)
                   }
                 }
        end)

      assert log =~ ~s(result=invalid)
    end

    test "gives 503 when the status server does not answer", %{conn: conn} do
      Deployer.StatusMock
      |> expect(:set_mode, fn "test_app", :automatic, "" -> {:error, :rescued} end)

      log =
        capture_log(fn ->
          assert conn
                 |> put("/v1/apps/test_app/mode", %{"mode" => "automatic"})
                 |> json_response(503)
        end)

      assert log =~ ~s(action=set_mode app="test_app" mode="automatic" result=unavailable)
    end

    test "refuses a mode it does not know, and a manual mode with no version", %{conn: conn} do
      Deployer.StatusMock |> expect(:set_mode, 0, fn _name, _mode, _version -> {:ok, %{}} end)

      for body <- [%{"mode" => "paused"}, %{"mode" => "manual"}, %{}] do
        assert conn |> put("/v1/apps/test_app/mode", body) |> json_response(422) == %{
                 "errors" => %{"detail" => "mode must be automatic, or manual with a version"}
               }
      end
    end
  end

  describe "scopes" do
    test "a read token gets 403 on every operate call, and the attempt is logged", %{conn: conn} do
      conn = bearer(conn, "read-token")

      log =
        capture_log(fn ->
          for {method, path} <- [
                {:post, "/v1/apps/test_app/restart"},
                {:delete, "/v1/apps/test_app/ghosted/4.5.7"},
                {:delete, "/v1/apps/test_app/ghosted"},
                {:put, "/v1/apps/test_app/mode"}
              ] do
            assert conn |> dispatch(@endpoint, method, path, nil) |> json_response(403)
          end
        end)

      assert log =~
               ~s(token=ci from=127.0.0.1 action="POST /v1/apps/test_app/restart" result=forbidden)

      for action <- [
            "DELETE /v1/apps/test_app/ghosted/4.5.7",
            "DELETE /v1/apps/test_app/ghosted",
            "PUT /v1/apps/test_app/mode"
          ] do
        assert log =~ ~s(token=ci from=127.0.0.1 action="#{action}" result=forbidden)
      end
    end

    test "a restart with a form content type and no body is not refused before the token check",
         %{conn: conn} do
      Process.register(self(), :test_app)

      capture_log(fn ->
        assert conn
               |> put_req_header("content-type", "application/x-www-form-urlencoded")
               |> post("/v1/apps/test_app/restart", "")
               |> json_response(202)
      end)

      assert_receive {:"$gen_cast", :restart_deployments}
    end

    test "an operate token does not imply read", %{conn: conn} do
      assert conn |> bearer("operate-only-token") |> get("/v1/apps") |> json_response(403)
    end
  end
end
