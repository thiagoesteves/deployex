defmodule DeployexWeb.AgentApi.SocketTest do
  use DeployexWeb.AgentApiCase

  alias DeployexWeb.AgentApi.Socket

  setup do
    put_api_tokens(token_entry("ci", "read", "read-token"))
  end

  test "connects with a valid token" do
    assert {:ok, socket} = connect(Socket, %{}, connect_info: %{auth_token: "read-token"})
    assert socket.assigns.api_token.name == "ci"
    assert Socket.id(socket) == nil
  end

  test "refuses a wrong or missing token" do
    assert connect(Socket, %{}, connect_info: %{auth_token: "wrong-token"}) == :error
    assert connect(Socket, %{}, connect_info: %{}) == :error
  end

  describe "websocket upgrade" do
    @token_protocol "phoenix, base64url.bearer.phx." <>
                      Base.encode64("read-token", padding: false)

    # The upgrade check reads the host header, which put_req_header/3 does not set
    defp upgrade(conn, subprotocols) do
      %{conn | req_headers: [{"host", "localhost"} | conn.req_headers]}
      |> put_req_header("connection", "upgrade")
      |> put_req_header("upgrade", "websocket")
      |> put_req_header("sec-websocket-version", "13")
      |> put_req_header("sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ==")
      |> put_req_header("sec-websocket-protocol", subprotocols)
      |> get("/v1/socket/websocket?vsn=2.0.0")
    end

    test "upgrades with the token as the Phoenix authToken", %{conn: conn} do
      conn =
        upgrade(
          conn,
          "phoenix, base64url.bearer.phx." <> Base.encode64("read-token", padding: false)
        )

      assert [{:websocket, _opts}] = Plug.Test.sent_upgrades(conn)
    end

    test "upgrades with an Origin that matches the address the client called", %{conn: conn} do
      conn = conn |> put_req_header("origin", "http://#{conn.host}") |> upgrade(@token_protocol)

      assert [{:websocket, _opts}] = Plug.Test.sent_upgrades(conn)
    end

    # Phoenix sends the 403, then its auth_token step raises on the sent conn
    test "refuses the upgrade from a page of another site", %{conn: conn} do
      assert_raise Plug.Conn.AlreadySentError, fn ->
        conn |> put_req_header("origin", "https://other.example.org") |> upgrade(@token_protocol)
      end

      assert_received {_ref, {403, _headers, _body}}
    end

    test "refuses the upgrade with a wrong token", %{conn: conn} do
      conn =
        upgrade(
          conn,
          "phoenix, base64url.bearer.phx." <> Base.encode64("wrong-token", padding: false)
        )

      assert conn.status == 403
      assert Plug.Test.sent_upgrades(conn) == []
    end
  end

  test "refuses a token sent as a connect parameter" do
    assert connect(Socket, %{"token" => "read-token"}, connect_info: %{}) == :error
  end
end
