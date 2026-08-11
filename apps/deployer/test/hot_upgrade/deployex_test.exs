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

  test "check/1 refuses a release built for a different OTP" do
    new_path = "/tmp/hotupgrade/deployex"
    on_exit(fn -> File.rm_rf(new_path) end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      # stands in for the extraction. The release carries its own erts, which identifies
      # the OTP it was built for
      File.mkdir_p!("#{new_path}/erts-0.0.1")
      {:ok, []}
    end)

    log =
      capture_log(fn ->
        assert {:error, {:otp_mismatch, versions}} = Deployex.check("/tmp/deployex-1.0.0.tar.gz")

        assert versions.package_erts == "0.0.1"
        assert versions.running_erts == to_string(:erlang.system_info(:version))
        assert versions.running_otp == to_string(:erlang.system_info(:otp_release))
      end)

    assert log =~ "built for a different OTP"
  end

  test "check/1 accepts a release built for the same OTP" do
    new_path = "/tmp/hotupgrade/deployex"
    on_exit(fn -> File.rm_rf(new_path) end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      File.mkdir_p!("#{new_path}/erts-#{:erlang.system_info(:version)}")
      {:ok, []}
    end)

    with_mock HotUpgradeApp, [:passthrough],
      check: fn _check -> {:ok, %Check{deploy: :hot_upgrade}} end do
      assert {:ok, %Check{}} = Deployex.check("/tmp/deployex-1.0.0.tar.gz")
    end
  end

  test "check/1 refuses a file that is not a deployex release" do
    # A monitored application's package uploaded by mistake. Nothing is extracted, the name
    # is rejected before anything runs
    log =
      capture_log(fn ->
        assert {:error, :invalid_release_file} = Deployex.check("/tmp/myumbrella-0.3.1.tar.gz")
      end)

    assert log =~ "is not a deployex release"
  end

  test "check/1 refuses a release file with no version" do
    log =
      capture_log(fn ->
        assert {:error, :invalid_release_file} = Deployex.check("/tmp/deployex-.tar.gz")
      end)

    assert log =~ "is not a deployex release"
  end

  test "execute/2 refuses a file that is not a deployex release" do
    assert capture_log(fn ->
             assert {:error, :invalid_release_file} =
                      Deployex.execute("/tmp/myumbrella-0.3.1.tar.gz", [])
           end) =~ "is not a deployex release"
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
      # the default is synchronous, so :ok really is the upgrade having finished
      assert capture_log(fn ->
               assert :ok = Deployex.execute("/tmp/deployex-1.0.0.tar.gz", [])
             end) =~ "Hot upgrade in deployex installed with success"
    end
  end

  test "execute/1 asynchronous does not claim the upgrade succeeded" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    with_mock HotUpgradeApp, [:passthrough],
      check: fn _check -> {:ok, %Check{deploy: :hot_upgrade}} end,
      # a cast returns :ok as soon as the request is accepted, the upgrade has not run
      execute: fn _check -> :ok end do
      log =
        capture_log(fn ->
          assert :ok = Deployex.execute("/tmp/deployex-1.0.0.tar.gz", sync_execution: false)
        end)

      assert log =~ "started"
      assert log =~ "the outcome follows"
      refute log =~ "installed with success"
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
             end) =~ "reason: :no_match_versions"
    end
  end

  test "execute/1 error before the release is installed says DeployEx keeps running" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    with_mock HotUpgradeApp, [:passthrough],
      check: fn _check -> {:ok, %Check{deploy: :hot_upgrade}} end,
      execute: fn _check -> {:error, {:not_installed, :make_relup}} end do
      log =
        capture_log(fn ->
          assert {:error, {:not_installed, :make_relup}} =
                   Deployex.execute("/tmp/deployex-1.0.0.tar.gz", [])
        end)

      # nothing was loaded, so the previous version really is the one still running
      assert log =~ "Nothing was installed"
      assert log =~ "is still running 0."
      assert log =~ "reason: :make_relup"
    end
  end

  test "execute/1 error after the release is installed does not claim the old version runs" do
    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, []} end)

    with_mock HotUpgradeApp, [:passthrough],
      check: fn _check -> {:ok, %Check{deploy: :hot_upgrade}} end,
      execute: fn _check -> {:error, :make_permanent} end do
      log =
        capture_log(fn ->
          assert {:error, :make_permanent} = Deployex.execute("/tmp/deployex-1.0.0.tar.gz", [])
        end)

      # the new code is already loaded at this point, claiming otherwise would be wrong
      assert log =~ "was installed before it failed"
      assert log =~ "may already be running 1.0.0"
      refute log =~ "is still running"
    end
  end
end
