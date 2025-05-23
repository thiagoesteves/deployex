defmodule Deployer.Release.LocalTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Fixture.Files, as: FixtureFiles
  alias Deployer.Release.Local
  alias Foundation.Catalog
  alias Foundation.Fixture.Catalog, as: FixtureCatalog

  setup do
    FixtureCatalog.cleanup()
  end

  test "get_current_version_map/1 optional fields" do
    version_map = %{"hash" => "local", "version" => "1.0.0"}

    FixtureCatalog.create_current_json()

    assert version_map == Local.download_version_map("testapp")
  end

  test "get_current_version_map/1 for local [success]" do
    assert capture_log(fn ->
             Local.download_version_map("myphoenixapp")
           end) =~ "Error downloading release version for myphoenixapp, reason: {:error, :enoent}"
  end

  test "download_release/2 success" do
    version = "5.0.0"
    name = "local_testapp"
    sname = Catalog.create_sname(name)
    new_path = Catalog.new_path(sname)

    Catalog.setup(sname)
    FixtureFiles.create_tar(name, version)

    assert :ok = Local.download_release(name, version, new_path)
  end
end
