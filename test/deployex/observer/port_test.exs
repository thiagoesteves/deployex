defmodule Deployex.Observer.PortTest do
  use ExUnit.Case, async: true

  import Mox

  alias Deployex.Observer.Port, as: ObserverPort

  setup :verify_on_exit!

  test "info/2" do
    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    invalid_port =
      "#Port<0.1000>"
      |> String.to_charlist()
      |> :erlang.list_to_port()

    [h | _] = :erlang.ports()
    assert %{connected: _, id: _, name: _, os_pid: _} = ObserverPort.info(h)
    assert %{connected: _, id: _, name: _, os_pid: _} = ObserverPort.info(Node.self(), h)
    assert :undefined = ObserverPort.info(Node.self(), invalid_port)
    assert :undefined = ObserverPort.info(Node.self(), nil)
  end
end
