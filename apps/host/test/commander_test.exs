defmodule Host.CommanderTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  alias Host.Commander

  test "run/2" do
    Host.CommanderMock
    |> expect(:run, fn "ls", [] -> {:ok, "any"} end)

    assert {:ok, "any"} = Commander.run("ls", [])
  end

  test "run_link/2" do
    Host.CommanderMock
    |> expect(:run_link, fn "ls", [] -> {:ok, "any"} end)

    assert {:ok, "any"} = Commander.run_link("ls", [])
  end

  test "stop/1" do
    Host.CommanderMock
    |> expect(:stop, fn 10 -> {:ok, "any"} end)

    assert {:ok, "any"} = Commander.stop(10)
  end

  test "send/2" do
    Host.CommanderMock
    |> expect(:send, fn 10, "msg" -> {:ok, "any"} end)

    assert {:ok, "any"} = Commander.send(10, "msg")
  end

  test "os_type/2" do
    Host.CommanderMock
    |> expect(:os_type, fn -> {:unix, :any} end)

    assert {:unix, :any} = Commander.os_type()
  end
end
