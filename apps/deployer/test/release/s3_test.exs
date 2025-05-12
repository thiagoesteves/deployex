defmodule Deployer.Release.S3Test do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Fixture.Nodes, as: FixtureNodes
  alias Deployer.Release.S3

  test "get_current_version_map/1 valid map" do
    version_map = %{"hash" => "test", "pre_commands" => [], "version" => "2.0.0"}

    with_mock ExAws, [], request: fn _command -> {:ok, %{body: Jason.encode!(version_map)}} end do
      assert version_map == S3.get_current_version_map()
    end
  end

  test "get_current_version_map/1 empty map" do
    with_mock ExAws, [], request: fn _command -> {:error, :any} end do
      assert nil == S3.get_current_version_map()
    end
  end

  test "download_and_unpack/2 success" do
    version = "5.0.0"
    name = "s3_testapp"
    sufix = "a1b2c3"
    node = FixtureNodes.test_node(name, sufix)

    Foundation.Catalog.setup(node)

    Deployer.StatusMock
    |> expect(:clear_new, fn ^node -> :ok end)
    |> expect(:current_version, fn ^node -> version end)

    Deployer.UpgradeMock
    |> expect(:check, fn ^node, _app_name, _app_lang, _path, _from, _to ->
      {:ok, :full_deployment}
    end)

    new_path = "/tmp/deployex/test/varlib/service/#{name}/#{name}-#{sufix}/new"

    with_mocks([
      {System, [], [cmd: fn "tar", ["-x", "-f", _download_path, "-C", ^new_path] -> {"", 0} end]},
      {ExAws, [], [request: fn _command -> {:ok, :done} end]}
    ]) do
      assert {:ok, :full_deployment} = S3.download_and_unpack(node, version)
    end
  end
end
