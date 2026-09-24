defmodule Deployer.SelfUpgrade.ExecutorTest do
  use ExUnit.Case, async: true
  import Mox

  alias Deployer.SelfUpgrade.Executor

  setup :verify_on_exit!

  test "hot_upgrade_command/1 delegates to the configured adapter" do
    Deployer.SelfUpgrade.ExecutorMock
    |> expect(:hot_upgrade_command, fn "1.2.3" -> {:ok, {"deployex.sh", [], []}} end)

    assert {:ok, {"deployex.sh", [], []}} = Executor.hot_upgrade_command("1.2.3")
  end
end
