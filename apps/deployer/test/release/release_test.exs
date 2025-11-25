defmodule Deployer.ReleaseTest do
  use ExUnit.Case, async: false

  import Mox
  import Mock

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Release
  alias Foundation.Catalog
  alias Foundation.Fixture.Catalog, as: FixtureCatalog

  alias Deployer.HotUpgrade

  setup do
    FixtureCatalog.cleanup()
  end

  test "get_current_version_map/1 automatic mode" do
    Deployer.ReleaseMock
    |> expect(:download_version_map, fn _app_name ->
      %{"version" => "1.0.0", "hash" => "local"}
    end)

    assert %Release.Version{hash: "local", pre_commands: [], version: "1.0.0"} ==
             Release.get_current_version_map("myelixir")
  end

  test "get_current_version_map/1 manual mode non-optional field" do
    name = "myelixir"
    config = Catalog.config(name)

    Catalog.config_update(name, %{
      config
      | mode: :manual,
        manual_version: %{"version" => "1.0.0", "hash" => "local"}
    })

    assert %Release.Version{hash: "local", pre_commands: [], version: "1.0.0"} ==
             Release.get_current_version_map(name)
  end

  test "get_current_version_map/1 manual mode" do
    name = "myelixir"

    expected_version = %Release.Version{
      hash: "local",
      pre_commands: ["cmd1"],
      version: "1.0.0"
    }

    config = Catalog.config(name)
    Catalog.config_update(name, %{config | mode: :manual, manual_version: expected_version})

    assert expected_version == Release.get_current_version_map(name)
  end

  test "download_and_unpack/1 - Startup - full deployment" do
    name = "myelixir"
    sname = Catalog.create_sname(name)
    new_path = Catalog.new_path(sname)

    release_version = "2.0.0"

    release_info = %Release{
      new_sname: sname,
      new_sname_new_path: new_path,
      current_version: nil,
      release_version: release_version
    }

    Deployer.ReleaseMock
    |> expect(:download_release, fn _app_name, ^release_version, _download_path -> :ok end)

    Deployer.HotUpgradeMock
    |> expect(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

    with_mock System, [:passthrough],
      cmd: fn "tar", ["-x", "-f", _download_path, "-C", ^new_path] -> {"", 0} end do
      assert {:ok, :full_deployment} == Release.download_and_unpack(release_info)
    end
  end

  test "download_and_unpack/1 - Empty new release - full deployment" do
    name = "myelixir"
    sname = Catalog.create_sname(name)
    new_path = Catalog.new_path(sname)
    current_path = Catalog.current_path(sname)

    current_version = "2.0.0"

    release_info = %Release{
      current_sname: sname,
      current_sname_current_path: current_path,
      current_sname_new_path: new_path,
      current_version: current_version,
      release_version: nil
    }

    Deployer.ReleaseMock
    |> expect(:download_release, fn _app_name, _release_version, _download_path -> :ok end)

    Deployer.HotUpgradeMock
    |> expect(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

    with_mock System, [:passthrough],
      cmd: fn "tar", ["-x", "-f", _download_path, "-C", _new_path] -> {"", 0} end do
      assert {:ok, :full_deployment} == Release.download_and_unpack(release_info)
    end
  end

  test "download_and_unpack/1 - Hot upgrade is detected" do
    name = "myelixir"
    sname_1 = Catalog.create_sname(name)
    new_path_1 = Catalog.new_path(sname_1)
    current_path_1 = Catalog.current_path(sname_1)
    sname_2 = Catalog.create_sname(name)
    new_path_2 = Catalog.new_path(sname_2)

    current_version = "1.0.0"
    release_version = "2.0.0"

    release_info = %Release{
      current_sname: sname_1,
      current_sname_current_path: current_path_1,
      current_sname_new_path: new_path_1,
      new_sname: sname_2,
      new_sname_new_path: new_path_2,
      current_version: current_version,
      release_version: release_version
    }

    Deployer.ReleaseMock
    |> expect(:download_release, fn _app_name, _release_version, _download_path -> :ok end)

    Deployer.HotUpgradeMock
    |> expect(:prepare_new_path, 2, fn _name, _language, _to_version, _new_path -> :ok end)
    |> expect(:check, fn %HotUpgrade.Check{
                           name: ^name,
                           language: "elixir",
                           download_path: _download_path,
                           current_path: ^current_path_1,
                           new_path: ^new_path_1,
                           from_version: ^current_version,
                           to_version: ^release_version
                         } ->
      {:ok, :hot_upgrade}
    end)

    with_mock System, [:passthrough],
      cmd: fn "tar", ["-x", "-f", _download_path, "-C", _new_path] -> {"", 0} end do
      assert {:ok, :hot_upgrade} == Release.download_and_unpack(release_info)
    end
  end

  test "download_and_unpack/1 - Hot upgrade is not detected" do
    name = "myelixir"
    sname_1 = Catalog.create_sname(name)
    new_path_1 = Catalog.new_path(sname_1)
    current_path_1 = Catalog.current_path(sname_1)
    sname_2 = Catalog.create_sname(name)
    new_path_2 = Catalog.new_path(sname_2)

    current_version = "1.0.0"
    release_version = "2.0.0"

    release_info = %Release{
      current_sname: sname_1,
      current_sname_current_path: current_path_1,
      current_sname_new_path: new_path_1,
      new_sname: sname_2,
      new_sname_new_path: new_path_2,
      current_version: current_version,
      release_version: release_version
    }

    Deployer.ReleaseMock
    |> expect(:download_release, fn ^name, ^release_version, _download_path -> :ok end)

    Deployer.HotUpgradeMock
    |> expect(:prepare_new_path, 2, fn _name, _language, _to_version, _new_path -> :ok end)
    |> expect(:check, fn %HotUpgrade.Check{
                           name: ^name,
                           language: "elixir",
                           download_path: _download_path,
                           current_path: ^current_path_1,
                           new_path: ^new_path_1,
                           from_version: ^current_version,
                           to_version: ^release_version
                         } ->
      {:ok, :full_deployment}
    end)

    with_mock System, [:passthrough],
      cmd: fn "tar", ["-x", "-f", _download_path, "-C", _new_path] -> {"", 0} end do
      assert {:ok, :full_deployment} == Release.download_and_unpack(release_info)
    end
  end
end
