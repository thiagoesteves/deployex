defmodule Deployer.Release.GcpStorageTest do
  use ExUnit.Case, async: false

  import Mock
  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Release.GcpStorage
  alias Foundation.Catalog

  test "download_version_map/1 valid map" do
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
      assert version_map == GcpStorage.download_version_map("myphoenixapp")
    end
  end

  test "download_version_map/1 empty map" do
    with_mocks([
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module -> {:error, :enoent} end
       ]},
      {Goth, [], [fetch!: fn _name -> %{token: "gcp-token"} end]}
    ]) do
      assert capture_log(fn ->
               GcpStorage.download_version_map("myphoenixapp")
             end) =~
               "Error downloading release version for myphoenixapp, reason: {:error, :enoent}"
    end
  end

  test "download_release/2 success" do
    version = "5.0.0"
    name = "myelixir"
    sname = Catalog.create_sname(name)
    new_path = Catalog.new_path(sname)

    Catalog.setup_new_node(sname)

    with_mocks([
      {System, [], [cmd: fn "tar", ["-x", "-f", _download_path, "-C", ^new_path] -> {"", 0} end]},
      {Goth, [], [fetch!: fn _name -> %{token: "gcp-token"} end]},
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module -> {:ok, %Finch.Response{body: "a.txt"}} end
       ]}
    ]) do
      assert :ok = GcpStorage.download_release(name, version, new_path)
    end
  end

  test "download_release/2 error" do
    version = "5.0.0"
    name = "myelixir"
    sname = Catalog.create_sname(name)
    new_path = Catalog.new_path(sname)

    Catalog.setup_new_node(sname)

    with_mocks([
      {Goth, [], [fetch!: fn _name -> %{token: "gcp-token"} end]},
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module -> {:error, :invalid_data} end
       ]}
    ]) do
      assert {:error, :invalid_data} = GcpStorage.download_release(name, version, new_path)
    end
  end
end
