defmodule DeployexWeb.AgentApi.OperateTest do
  use ExUnit.Case, async: true

  alias DeployexWeb.AgentApi.Operate

  describe "remote_ip/1" do
    test "prints an IPv4 client of an endpoint bound to :: as IPv4" do
      conn = %Plug.Conn{remote_ip: {0, 0, 0, 0, 0, 0xFFFF, 0x0A00, 0x0114}}
      assert Operate.remote_ip(conn) == "10.0.1.20"
    end

    test "prints IPv4 and other IPv6 addresses as they are" do
      assert Operate.remote_ip(%Plug.Conn{remote_ip: {10, 0, 1, 20}}) == "10.0.1.20"
      assert Operate.remote_ip(%Plug.Conn{remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}}) == "::1"
    end
  end
end
