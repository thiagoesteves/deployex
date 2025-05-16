defmodule Deployer.Release.S3Test do
  use ExUnit.Case, async: false

  import Mock
  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Fixture.Nodes, as: FixtureNodes
  alias Deployer.Release.S3
  alias Foundation.Catalog

  test "get_current_version_map/1 valid map" do
    version_map = %{"hash" => "test", "pre_commands" => [], "version" => "2.0.0"}

    with_mock ExAws, [], request: fn _command -> {:ok, %{body: Jason.encode!(version_map)}} end do
      assert version_map == S3.download_version_map("myphoenixapp")
    end
  end

  test "get_current_version_map/1 empty map" do
    with_mock ExAws, [], request: fn _command -> {:error, :enoent} end do
      assert capture_log(fn ->
               S3.download_version_map("myphoenixapp")
             end) =~
               "Error downloading release version for myphoenixapp, reason: {:error, :enoent}"
    end
  end

  test "download_and_unpack/2 success" do
    version = "5.0.0"
    name = "s3_testapp"
    sufix = "a1b2c3"
    node = FixtureNodes.test_node(name, sufix)

    Catalog.setup(node)

    new_path = Catalog.new_path(node)

    with_mocks([
      {System, [], [cmd: fn "tar", ["-x", "-f", _download_path, "-C", ^new_path] -> {"", 0} end]},
      {ExAws, [], [request: fn _command -> {:ok, :done} end]}
    ]) do
      assert :ok = S3.download_release(name, version, new_path)
    end
  end
end
