defmodule Deployer.Release.GcpStorageTest do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Fixture.Nodes, as: FixtureNodes
  alias Deployer.Release.GcpStorage

  test "get_current_version_map/1 valid map" do
    version_map = %{"hash" => "test", "pre_commands" => [], "version" => "2.0.0"}

    with_mocks([
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module ->
           {:ok, %Finch.Response{body: Jason.encode!(version_map)}}
         end
       ]},
      {Goth, [], [fetch!: fn _name -> %{token: "gcp-token"} end]}
    ]) do
      assert version_map == GcpStorage.get_current_version_map()
    end
  end

  test "get_current_version_map/1 empty map" do
    with_mocks([
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module -> {:error, :any} end
       ]},
      {Goth, [], [fetch!: fn _name -> %{token: "gcp-token"} end]}
    ]) do
      assert nil == GcpStorage.get_current_version_map()
    end
  end

  test "download_and_unpack/2 success" do
    version = "5.0.0"
    name = "testapp"
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
      {Goth, [], [fetch!: fn _name -> %{token: "gcp-token"} end]},
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module -> {:ok, %Finch.Response{body: ""}} end
       ]}
    ]) do
      assert {:ok, :full_deployment} = GcpStorage.download_and_unpack(node, version)
    end
  end

  test "download_and_unpack/2 error" do
    version = "5.0.0"
    node = :invalid@node

    with_mocks([
      {Goth, [], [fetch!: fn _name -> %{token: "gcp-token"} end]},
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module -> {:error, :invalid_data} end
       ]}
    ]) do
      assert_raise RuntimeError, fn ->
        {:ok, :full_deployment} = GcpStorage.download_and_unpack(node, version)
      end
    end
  end
end
