defmodule Deployer.SelfUpgrade.Source.GcpTest do
  use ExUnit.Case, async: true

  alias Deployer.SelfUpgrade.Source.Gcp

  defmodule FakeOk do
    def attribute, do: {:ok, "0.9.15"}
  end

  defmodule FakeNoAttr do
    def attribute, do: {:error, :not_found}
  end

  defmodule FakeAttrError do
    def attribute, do: {:error, :boom}
  end

  setup do
    on_exit(fn -> Application.delete_env(:deployer, Gcp) end)
  end

  test "returns the attribute value" do
    Application.put_env(:deployer, Gcp, client: FakeOk)
    assert {:ok, "0.9.15"} = Gcp.desired_version()
  end

  test "returns :none when the attribute is missing" do
    Application.put_env(:deployer, Gcp, client: FakeNoAttr)
    assert :none = Gcp.desired_version()
  end

  test "a generic (non-404) attribute error propagates as an error" do
    Application.put_env(:deployer, Gcp, client: FakeAttrError)
    assert {:error, _} = Gcp.desired_version()
  end
end
