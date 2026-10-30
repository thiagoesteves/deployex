defmodule DeployexWeb.LogsExportControllerTest do
  use DeployexWeb.ConnCase, async: false

  import Mox

  alias Foundation.Catalog
  alias Sentinel.Logs.Message

  setup [:set_mox_global, :verify_on_exit!]

  setup do
    sname = Catalog.create_sname("myelixir")
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)

    Sentinel.LogsMock
    |> stub(:list_active_snames, fn -> [] end)
    |> stub(:get_types_by_sname, fn _sname -> [:stdout] end)
    |> stub(:list_data_by_sname_log_type, fn _sname, _type, _options ->
      [%Message{timestamp: System.os_time(:millisecond), log: "booted"}]
    end)

    %{sname: sname}
  end

  describe "a logged in user" do
    setup :log_in_default_user

    @describetag :capture_log

    test "downloads the lines as .log text", %{conn: conn, sname: sname} do
      conn = get(conn, ~p"/logs/export?#{%{source: sname, minutes: 30}}")

      assert response(conn, 200) =~ ~r/^\S+Z #{sname} stdout booted\n$/
      assert response_content_type(conn, :text) =~ "text/plain"

      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~r/attachment; filename="deployex-logs-.+\.log"/
    end

    test "downloads the lines as .jsonl", %{conn: conn, sname: sname} do
      conn = get(conn, ~p"/logs/export?#{%{source: sname, format: "jsonl"}}")

      assert [line] = conn |> response(200) |> String.split("\n", trim: true)

      assert %{"source" => ^sname, "stream" => "stdout", "message" => "booted"} =
               Jason.decode!(line)

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/x-ndjson"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~r/filename="deployex-logs-.+\.jsonl"/
    end

    test "gets an empty file for a source this host does not have", %{conn: conn} do
      conn = get(conn, ~p"/logs/export?#{%{source: "other-abc123"}}")
      assert response(conn, 200) == ""
    end
  end

  @tag :capture_log
  test "a visitor is sent to log in", %{conn: conn, sname: sname} do
    conn = get(conn, ~p"/logs/export?#{%{source: sname}}")
    assert redirected_to(conn) == "/users/log_in"
  end
end
