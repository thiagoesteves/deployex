defmodule Deployer.ReleaseTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Release
  alias Foundation.Catalog
  alias Foundation.Fixture.Catalog, as: FixtureCatalog

  setup do
    FixtureCatalog.cleanup()
  end

  test "get_current_version_map/1 automatic mode" do
    Deployer.ReleaseMock
    |> expect(:get_current_version_map, fn ->
      %{"version" => "1.0.0", "hash" => "local"}
    end)

    assert %Deployer.Release.Version{hash: "local", pre_commands: [], version: "1.0.0"} ==
             Release.get_current_version_map()
  end

  test "get_current_version_map/1 manual mode non-optional field" do
    config = Catalog.config()

    Catalog.config_update(%{
      config
      | mode: :manual,
        manual_version: %{"version" => "1.0.0", "hash" => "local"}
    })

    assert %Deployer.Release.Version{hash: "local", pre_commands: [], version: "1.0.0"} ==
             Release.get_current_version_map()
  end

  test "get_current_version_map/1 manual mode" do
    expected_version = %Deployer.Release.Version{
      hash: "local",
      pre_commands: ["cmd1"],
      version: "1.0.0"
    }

    config = Catalog.config()
    Catalog.config_update(%{config | mode: :manual, manual_version: expected_version})

    assert expected_version == Release.get_current_version_map()
  end
end
