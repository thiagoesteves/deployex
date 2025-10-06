defmodule DeployexWeb.HealthControllerTest do
  use DeployexWeb.ConnCase, async: true

  describe "health/2" do
    test "returns ok status with timestamp", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200) == %{
               "status" => "ok",
               "timestamp" => json_response(conn, 200)["timestamp"]
             }
    end

    test "returns valid ISO8601 timestamp", %{conn: conn} do
      conn = get(conn, ~p"/health")
      response = json_response(conn, 200)

      assert response["status"] == "ok"
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(response["timestamp"])
    end

    test "timestamp is recent", %{conn: conn} do
      before = DateTime.utc_now()
      conn = get(conn, ~p"/health")
      after_time = DateTime.utc_now()

      response = json_response(conn, 200)
      {:ok, timestamp, _} = DateTime.from_iso8601(response["timestamp"])

      assert DateTime.compare(timestamp, before) in [:gt, :eq]
      assert DateTime.compare(timestamp, after_time) in [:lt, :eq]
    end

    test "returns correct content type", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers
    end
  end
end
