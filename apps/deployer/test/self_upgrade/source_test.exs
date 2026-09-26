defmodule Deployer.SelfUpgrade.SourceTest do
  use ExUnit.Case, async: true
  import Mox

  alias Deployer.SelfUpgrade.Source

  setup :verify_on_exit!

  test "desired_version/0 delegates to the configured adapter" do
    Deployer.SelfUpgrade.SourceMock
    |> expect(:desired_version, fn -> {:ok, "0.9.15"} end)

    assert {:ok, "0.9.15"} = Source.desired_version()
  end
end
