defmodule Deployer.HotUpgrade.DeployexTest do
  use ExUnit.Case, async: false

  import Mox
  import Mock
  import ExUnit.CaptureLog

  alias Deployer.HotUpgrade.Application, as: HotUpgradeApp
  alias Deployer.HotUpgrade.Check
  alias Deployer.HotUpgrade.Deployex

  setup :set_mox_global
  setup :verify_on_exit!

  test "check/1 success" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    with_mock HotUpgradeApp, [:passthrough],
      check: fn _check -> {:ok, %Check{deploy: :hot_upgrade}} end do
      assert {:ok, %Check{}} = Deployex.check("/tmp/deployex-1.0.0.tar.gz")
    end
  end

  test "check/1 fail to untar" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:error, ["invalid"]} end)

    assert capture_log(fn ->
             assert {:error, ["invalid"]} =
                      Deployex.check("/tmp/deployex-1.0.0.tar.gz")
           end) =~ "Hot upgrade not supported for this release"
  end

  test "check/1 invalid hotupgrade" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    with_mock HotUpgradeApp, [:passthrough],
      check: fn _check -> {:ok, %Check{deploy: :full_deployment}} end do
      assert {:error, :full_deployment} =
               Deployex.check("/tmp/deployex-1.0.0.tar.gz")
    end
  end

  test "execute/1 success" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    with_mock HotUpgradeApp, [:passthrough],
      check: fn _check -> {:ok, %Check{deploy: :hot_upgrade}} end,
      execute: fn _check -> :ok end do
      assert capture_log(fn ->
               assert :ok = Deployex.execute("/tmp/deployex-1.0.0.tar.gz", [])
             end) =~ "Hot upgrade in deployex installed with success"
    end
  end

  test "execute/1 error" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    with_mock HotUpgradeApp, [:passthrough],
      check: fn _check -> {:ok, %Check{deploy: :hot_upgrade}} end,
      execute: fn _check -> {:error, :no_match_versions} end do
      assert capture_log(fn ->
               assert {:error, :no_match_versions} =
                        Deployex.execute("/tmp/deployex-1.0.0.tar.gz", [])
             end) =~ "Hot upgrade failed: :no_match_versions"
    end
  end
end
