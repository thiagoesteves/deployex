defmodule Deployer.SelfUpgrade.ExecutorTest do
  use ExUnit.Case, async: true
  import Mox

  alias Deployer.SelfUpgrade.Executor

  setup :verify_on_exit!

  test "hot_upgrade/1 delegates to the configured adapter" do
    Deployer.SelfUpgrade.ExecutorMock
    |> expect(:hot_upgrade, fn "1.2.3" -> :ok end)

    assert :ok = Executor.hot_upgrade("1.2.3")
  end
end
