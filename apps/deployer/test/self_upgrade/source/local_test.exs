defmodule Deployer.SelfUpgrade.Source.LocalTest do
  use ExUnit.Case, async: true

  alias Deployer.SelfUpgrade.Source.Local

  test "returns the configured version" do
    Application.put_env(:deployer, Local, version: "1.2.3")
    on_exit(fn -> Application.delete_env(:deployer, Local) end)
    assert {:ok, "1.2.3"} = Local.desired_version()
  end

  test "returns :none when unset" do
    Application.delete_env(:deployer, Local)
    assert :none = Local.desired_version()
  end

  test "returns :none when the configured version is empty" do
    Application.put_env(:deployer, Local, version: "")
    on_exit(fn -> Application.delete_env(:deployer, Local) end)
    assert :none = Local.desired_version()
  end
end
