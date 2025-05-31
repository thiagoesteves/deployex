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

  test "current_version/1" do
    Deployer.StatusMock
    |> expect(:current_version, fn _sname -> "0.0.0" end)

    assert "0.0.0" = Status.current_version("myelixir-1234")
  end

  test "current_version/0" do
    Deployer.StatusMock
    |> expect(:subscribe, fn -> :ok end)

    assert :ok = Status.subscribe()
  end

  test "set_current_version_map/3" do
    Deployer.StatusMock
    |> expect(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)

    assert :ok = Status.set_current_version_map("myelixir-1234", %Deployer.Release.Version{}, [])
  end

  test "add_ghosted_version/1" do
    Deployer.StatusMock
    |> expect(:add_ghosted_version, fn _version_map -> {:ok, []} end)

    assert {:ok, []} = Status.add_ghosted_version(%{})
  end

  test "history_version_list/2" do
    Deployer.StatusMock
    |> expect(:history_version_list, fn _name, _options -> [] end)

    assert [] = Status.history_version_list("myelixir", [])
  end

  test "update/1" do
    Deployer.StatusMock
    |> expect(:update, fn _sname -> :ok end)

    assert :ok = Status.update("sname")
  end

  test "set_mode/2" do
    mode = :automatic
    version = "9.9.9"

    Deployer.StatusMock
    |> expect(:set_mode, fn _name, mode, version -> {:ok, %{mode: mode, version: version}} end)

    assert {:ok, %{mode: ^mode, version: ^version}} = Status.set_mode("myelixir", mode, version)
  end
end
