defmodule Deployex.ReleaseTest do
  use ExUnit.Case, async: false

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
end
