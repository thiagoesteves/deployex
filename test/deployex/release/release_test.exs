defmodule Deployex.ReleaseTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.Fixture.Storage, as: FixtureStorage
  alias Deployex.Release
  alias Deployex.Storage

  setup do
    FixtureStorage.cleanup()
  end

  test "get_current_version_map/1 automatic mode" do
    Deployex.ReleaseMock
    |> expect(:get_current_version_map, fn ->
      %{"version" => "1.0.0", "hash" => "local"}
    end)

    assert %Deployex.Release.Version{hash: "local", pre_commands: [], version: "1.0.0"} ==
             Release.get_current_version_map()
  end

  test "get_current_version_map/1 manual mode non-optional field" do
    config = Storage.config()

    Storage.config_update(%{
      config
      | mode: :manual,
        manual_version: %{"version" => "1.0.0", "hash" => "local"}
    })

    assert %Deployex.Release.Version{hash: "local", pre_commands: [], version: "1.0.0"} ==
             Release.get_current_version_map()
  end

  test "get_current_version_map/1 manual mode" do
    expected_version = %Deployex.Release.Version{
      hash: "local",
      pre_commands: ["cmd1"],
      version: "1.0.0"
    }

    config = Storage.config()
    Storage.config_update(%{config | mode: :manual, manual_version: expected_version})

    assert expected_version == Release.get_current_version_map()
  end
end
