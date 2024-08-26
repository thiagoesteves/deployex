defmodule Deployex.Release.LocalTest do
  use ExUnit.Case, async: false

  import Mock
  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.Fixture.Storage
  alias Deployex.Release.Local

  setup do
    Storage.cleanup()
  end

  test "get_current_version_map/1 optional fields" do
    Deployex.ReleaseMock
    |> expect(:get_current_version_map, fn ->
      %{"version" => "1.0.0", "hash" => "local"}
    end)

    assert %{"hash" => "local", "pre_commands" => [], "version" => "1.0.0"} ==
             Deployex.Release.get_current_version_map()
  end

  test "get_current_version_map/1 for local [success]" do
    assert capture_log(fn ->
             assert nil == Local.get_current_version_map()
           end) =~ "Invalid version map at: /tmp/testapp/versions/testapp/local/current.json"
  end

  test "get_current_version_map/1 for local [error]" do
    expected_map = %{"version" => "2.0.0", "hash" => "123456789"}
    Storage.create_current_json(expected_map)

    assert expected_map == Local.get_current_version_map()
  end

  test "download_and_unpack/2 success" do
    version = "5.0.0"
    instance = 999

    Deployex.StatusMock
    |> expect(:clear_new, fn ^instance -> :ok end)
    |> expect(:current_version, fn ^instance -> version end)

    Deployex.UpgradeMock
    |> expect(:check, fn ^instance, _path, _from, _to -> {:ok, :full_deployment} end)

    download_path = "/tmp/testapp/dist/testapp/testapp-5.0.0.tar.gz"
    new_path = "/tmp/deployex/test/varlib/service/testapp/999/new"

    with_mock System, cmd: fn "tar", ["-x", "-f", ^download_path, "-C", ^new_path] -> {"", 0} end do
      assert {:ok, :full_deployment} = Local.download_and_unpack(instance, version)
    end
  end
end
