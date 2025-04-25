defmodule Deployer.StatusTest do
  use ExUnit.Case, async: false

  import Mox
  setup :verify_on_exit!

  alias Deployer.Status

  test "monitoring/0" do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, []} end)

    assert {:ok, []} = Status.monitoring()
  end

  test "monitored_app_name/0" do
    Deployer.StatusMock
    |> expect(:monitored_app_name, fn -> "test" end)

    assert "test" = Status.monitored_app_name()
  end

  test "monitored_app_lang/0" do
    Deployer.StatusMock
    |> expect(:monitored_app_lang, fn -> "test" end)

    assert "test" = Status.monitored_app_lang()
  end

  test "current_version/1" do
    Deployer.StatusMock
    |> expect(:current_version, fn _instance -> "0.0.0" end)

    assert "0.0.0" = Status.current_version(1)
  end

  test "current_version/0" do
    Deployer.StatusMock
    |> expect(:subscribe, fn -> :ok end)

    assert :ok = Status.subscribe()
  end

  test "set_current_version_map/3" do
    Deployer.StatusMock
    |> expect(:set_current_version_map, fn _instance, _release, _attrs -> :ok end)

    assert :ok = Status.set_current_version_map(0, %Deployer.Release.Version{}, [])
  end

  test "add_ghosted_version/1" do
    Deployer.StatusMock
    |> expect(:add_ghosted_version, fn _version_map -> {:ok, []} end)

    assert {:ok, []} = Status.add_ghosted_version(%{})
  end

  test "ghosted_version_list/0" do
    Deployer.StatusMock
    |> expect(:ghosted_version_list, fn -> [] end)

    assert [] = Status.ghosted_version_list()
  end

  test "history_version_list/0" do
    Deployer.StatusMock
    |> expect(:history_version_list, fn -> [] end)

    assert [] = Status.history_version_list()
  end

  test "history_version_list/1" do
    Deployer.StatusMock
    |> expect(:history_version_list, fn _instance -> [] end)

    assert [] = Status.history_version_list(0)
  end

  test "clear_new/1" do
    Deployer.StatusMock
    |> expect(:clear_new, fn _instance -> :ok end)

    assert :ok = Status.clear_new(0)
  end

  test "update/1" do
    Deployer.StatusMock
    |> expect(:update, fn _instance -> :ok end)

    assert :ok = Status.update(0)
  end

  test "set_mode/2" do
    mode = :automatic
    version = "9.9.9"

    Deployer.StatusMock
    |> expect(:set_mode, fn mode, version -> {:ok, %{mode: mode, version: version}} end)

    assert {:ok, %{mode: ^mode, version: ^version}} = Status.set_mode(mode, version)
  end
end
