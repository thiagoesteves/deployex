defmodule Deployer.ReleaseTest do
  use ExUnit.Case, async: false

  import Mox
  import Mock

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Release
  alias Foundation.Catalog
  alias Deployer.Fixture.Nodes, as: FixtureNodes
  alias Foundation.Fixture.Catalog, as: FixtureCatalog

  setup do
    FixtureCatalog.cleanup()
  end

  test "get_current_version_map/1 automatic mode" do
    Deployer.ReleaseMock
    |> expect(:download_version_map, fn _app_name ->
      %{"version" => "1.0.0", "hash" => "local"}
    end)

    assert %Deployer.Release.Version{hash: "local", pre_commands: [], version: "1.0.0"} ==
             Release.get_current_version_map("testapp")
  end

  test "get_current_version_map/1 manual mode non-optional field" do
    config = Catalog.config()

    Catalog.config_update(%{
      config
      | mode: :manual,
        manual_version: %{"version" => "1.0.0", "hash" => "local"}
    })

    assert %Deployer.Release.Version{hash: "local", pre_commands: [], version: "1.0.0"} ==
             Release.get_current_version_map("testapp")
  end

  test "get_current_version_map/1 manual mode" do
    expected_version = %Deployer.Release.Version{
      hash: "local",
      pre_commands: ["cmd1"],
      version: "1.0.0"
    }

    config = Catalog.config()
    Catalog.config_update(%{config | mode: :manual, manual_version: expected_version})

    assert expected_version == Release.get_current_version_map("testapp")
  end

  test "download_and_unpack/1 - Startup - full deployment" do
    name = "release_testapp"
    suffix = "abc123"

    node = FixtureNodes.test_node(name, suffix)

    release_version = "2.0.0"

    release_info = %Deployer.Release{
      current_node: nil,
      new_node: node,
      current_version: nil,
      release_version: release_version
    }

    Deployer.ReleaseMock
    |> expect(:download_release, fn _app_name, ^release_version, _download_path -> :ok end)

    new_path = Catalog.new_path(node)

    with_mock System, cmd: fn "tar", ["-x", "-f", _download_path, "-C", ^new_path] -> {"", 0} end do
      assert {:ok, :full_deployment} == Release.download_and_unpack(release_info)
    end
  end

  test "download_and_unpack/1 - Empty new release - full deployment" do
    name = "release_testapp"
    suffix = "abc123"

    node = FixtureNodes.test_node(name, suffix)

    current_version = "2.0.0"

    release_info = %Deployer.Release{
      current_node: node,
      new_node: nil,
      current_version: current_version,
      release_version: nil
    }

    Deployer.ReleaseMock
    |> expect(:download_release, fn _app_name, _release_version, _download_path -> :ok end)

    with_mock System, cmd: fn "tar", ["-x", "-f", _download_path, "-C", _new_path] -> {"", 0} end do
      assert {:ok, :full_deployment} == Release.download_and_unpack(release_info)
    end
  end

  test "download_and_unpack/1 - Hot upgrade is detected" do
    name = "release_testapp"
    suffix1 = "abc123"
    suffix2 = "123abc"

    node1 = FixtureNodes.test_node(name, suffix1)
    node2 = FixtureNodes.test_node(name, suffix2)

    current_version = "1.0.0"
    release_version = "2.0.0"

    release_info = %Deployer.Release{
      current_node: node1,
      new_node: node2,
      current_version: current_version,
      release_version: release_version
    }

    Deployer.ReleaseMock
    |> expect(:download_release, fn _app_name, _release_version, _download_path -> :ok end)

    Deployer.UpgradeMock
    |> expect(:check, fn ^node1,
                         ^name,
                         "elixir",
                         _download_path,
                         ^current_version,
                         ^release_version ->
      {:ok, :hot_upgrade}
    end)

    with_mock System, cmd: fn "tar", ["-x", "-f", _download_path, "-C", _new_path] -> {"", 0} end do
      assert {:ok, :hot_upgrade} == Release.download_and_unpack(release_info)
    end
  end

  test "download_and_unpack/1 - Hot upgrade is not detected" do
    name = "release_testapp"
    suffix1 = "abc123"
    suffix2 = "123abc"

    node1 = FixtureNodes.test_node(name, suffix1)
    node2 = FixtureNodes.test_node(name, suffix2)

    current_version = "1.0.0"
    release_version = "2.0.0"

    release_info = %Deployer.Release{
      current_node: node1,
      new_node: node2,
      current_version: current_version,
      release_version: release_version
    }

    Deployer.ReleaseMock
    |> expect(:download_release, fn _app_name, _release_version, _download_path -> :ok end)

    Deployer.UpgradeMock
    |> expect(:check, fn ^node1,
                         ^name,
                         "elixir",
                         _download_path,
                         ^current_version,
                         ^release_version ->
      {:ok, :full_deployment}
    end)

    with_mock System, cmd: fn "tar", ["-x", "-f", _download_path, "-C", _new_path] -> {"", 0} end do
      assert {:ok, :full_deployment} == Release.download_and_unpack(release_info)
    end
  end
end
