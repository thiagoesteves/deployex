defmodule Deployex.Observer.ProcessTest do
  use ExUnit.Case, async: false

  import Mox

  alias Deployex.Observer.Process, as: ObserverPort

  setup :verify_on_exit!

  test "info/1" do
    Deployex.RpcMock
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    kernel_pid = :application_controller.get_master(:kernel)

    assert %{error_handler: :error_handler, memory: _, relations: %{links: [head, tail]}} =
             ObserverPort.info(kernel_pid)

    assert %{error_handler: :error_handler, memory: _, relations: _} = ObserverPort.info(head)
    assert %{error_handler: :error_handler, memory: _, relations: _} = ObserverPort.info(tail)
    invalid_pid = "<0.11111.0>" |> String.to_charlist() |> :erlang.list_to_pid()
    assert :undefined = ObserverPort.info(invalid_pid)
    supervisor = Process.whereis(Elixir.Deployex.Supervisor)

    assert %{error_handler: :error_handler, memory: _, relations: _} =
             ObserverPort.info(supervisor)
  end
end
