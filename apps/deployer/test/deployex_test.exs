defmodule Deployer.DeployexTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  alias Deployer.Deployex
  alias Deployer.Upgrade.Check

  setup :set_mox_global
  setup :verify_on_exit!

  test "force_terminate/0" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    assert capture_log(fn ->
             assert :ok = Deployex.force_terminate(1)
           end) =~ "Deployex was requested to terminate, see you soon!!!"
  end

  test "hot_upgrade_check/1 success" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    Deployer.UpgradeMock
    |> expect(:check, fn _check -> {:ok, :hot_upgrade} end)

    assert {:ok, %Check{}} = Deployex.hot_upgrade_check("/tmp/deployex-1.0.0.tar.gz")
  end

  test "hot_upgrade_check/1 fail to untar" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:error, ["invalid"]} end)

    assert capture_log(fn ->
             assert {:error, ["invalid"]} =
                      Deployex.hot_upgrade_check("/tmp/deployex-1.0.0.tar.gz")
           end) =~ "Hot upgrade not supported for this release"
  end

  test "hot_upgrade_check/1 invalid hotupgrade" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    Deployer.UpgradeMock
    |> expect(:check, fn _check -> {:ok, :full_deployment} end)

    assert {:error, :full_deployment} =
             Deployex.hot_upgrade_check("/tmp/deployex-1.0.0.tar.gz")
  end

  test "hot_upgrade/1 success" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    Deployer.UpgradeMock
    |> expect(:check, fn _check -> {:ok, :hot_upgrade} end)
    |> expect(:execute, fn _check -> :ok end)

    assert capture_log(fn ->
             assert :ok = Deployex.hot_upgrade("/tmp/deployex-1.0.0.tar.gz")
           end) =~ "Hot upgrade in deployex installed with success"
  end

  test "hot_upgrade/1 error" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    Deployer.UpgradeMock
    |> expect(:check, fn _check -> {:ok, :hot_upgrade} end)
    |> expect(:execute, fn _check -> {:error, :no_match_versions} end)

    assert capture_log(fn ->
             assert {:error, :no_match_versions} =
                      Deployex.hot_upgrade("/tmp/deployex-1.0.0.tar.gz")
           end) =~ "Hot upgrade failed: :no_match_versions"
  end

  test "make_permanent/1 success" do
    node = Node.self()

    Foundation.RpcMock
    |> expect(:call, fn ^node, :release_handler, :make_permanent, [~c"1.2.3"], :infinity ->
      :ok
    end)

    refute "1.2.3" == Enum.at(Foundation.Catalog.versions("deployex", []), 0).version

    assert :ok = Deployex.make_permanent("/tmp/deployex-1.2.3.tar.gz")

    assert "1.2.3" == Enum.at(Foundation.Catalog.versions("deployex", []), 0).version
  end

  test "make_permanent/1 error" do
    node = Node.self()

    Foundation.RpcMock
    |> expect(:call, fn ^node, :release_handler, :make_permanent, [~c"1.0.0"], :infinity ->
      {:error, {:no_such_release, ~c"0.8.1"}}
    end)

    assert capture_log(fn ->
             assert {:error, _} = Deployex.make_permanent("/tmp/deployex-1.0.0.tar.gz")
           end) =~
             "Error while trying to set a permanent version for 1.0.0, reason: {:error, {:no_such_release, ~c\"0.8.1\"}}"
  end
end
