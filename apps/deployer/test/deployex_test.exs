defmodule Deployer.DeployexTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  alias Deployer.Deployex

  setup :set_mox_global
  setup :verify_on_exit!

  test "force_terminate/0" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    assert capture_log(fn ->
             assert :ok = Deployex.force_terminate(1)
           end) =~ "Deployex was requested to terminate, see you soon!!!"
  end
end
