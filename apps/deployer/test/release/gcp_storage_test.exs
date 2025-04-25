defmodule Deployer.Release.GcpStorageTest do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

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
    instance = 999

    Deployer.StatusMock
    |> expect(:clear_new, fn ^instance -> :ok end)
    |> expect(:current_version, fn ^instance -> version end)

    Deployer.UpgradeMock
    |> expect(:check, fn ^instance, _app_name, _app_lang, _path, _from, _to ->
      {:ok, :full_deployment}
    end)

    new_path = "/tmp/deployex/test/varlib/service/testapp/999/new"

    with_mocks([
      {System, [], [cmd: fn "tar", ["-x", "-f", _download_path, "-C", ^new_path] -> {"", 0} end]},
      {Goth, [], [fetch!: fn _name -> %{token: "gcp-token"} end]},
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module -> {:ok, %Finch.Response{body: ""}} end
       ]}
    ]) do
      assert {:ok, :full_deployment} = GcpStorage.download_and_unpack(instance, version)
    end
  end

  test "download_and_unpack/2 error" do
    version = "5.0.0"
    instance = 999

    with_mocks([
      {Goth, [], [fetch!: fn _name -> %{token: "gcp-token"} end]},
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module -> {:error, :invalid_data} end
       ]}
    ]) do
      assert_raise RuntimeError, fn ->
        {:ok, :full_deployment} = GcpStorage.download_and_unpack(instance, version)
      end
    end
  end
end
