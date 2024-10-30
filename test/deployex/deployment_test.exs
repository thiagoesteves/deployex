defmodule Deployex.DeploymentTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.Deployment
  alias Deployex.Fixture.Storage, as: FixtureStorage
  alias Deployex.Storage

  setup do
    FixtureStorage.cleanup()
  end

  describe "Initialization tests" do
    test "init/1" do
      name = "#{__MODULE__}-init-000" |> String.to_atom()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 5_000,
                 name: name
               )

      assert {:error, {:already_started, _pid}} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 5_000,
                 name: name
               )
    end

    test "Initialization with version not configured" do
      name = "#{__MODULE__}-init-001" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _instance ->
        Process.send_after(pid, {:handle_ref_event, ref}, 100)
        nil
      end)

      Deployex.ReleaseMock
      |> stub(:get_current_version_map, fn -> %Deployex.Release.Version{} end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 10,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Initialization with version configured" do
      name = "#{__MODULE__}-init-002" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> expect(:current_version, fn _instance -> "1.2.3" end)

      Deployex.MonitorMock
      |> expect(:start_service, 1, fn _language, _instance, _deploy_ref, _options ->
        send(pid, {:handle_ref_event, ref})
        {:ok, self()}
      end)

      Deployex.ReleaseMock
      |> expect(:get_current_version_map, 0, fn -> %Deployex.Release.Version{} end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 10,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end
  end

  describe "Checking deployment" do
    test "Check for new version - full deployment - no pre-commands" do
      name = "#{__MODULE__}-check-000" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> expect(:current_version, 2, fn _instance -> "1.0.0" end)
      |> expect(:update, 1, fn _instance -> :ok end)
      |> expect(:set_current_version_map, 1, fn _instance, _release, _attrs -> :ok end)

      Deployex.MonitorMock
      |> expect(:start_service, 2, fn _language, _instance, _deploy_ref, _options ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, 1, fn _instance -> :ok end)
      |> expect(:run_pre_commands, 0, fn _instance, _release, _type -> {:ok, []} end)

      Deployex.ReleaseMock
      |> expect(:get_current_version_map, 1, fn ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> expect(:download_and_unpack, 1, fn _instance, "2.0.0" ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 10,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Check for new version - ignore ghosted version" do
      name = "#{__MODULE__}-check-001" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [%{version: "2.0.0"}] end)
      |> expect(:update, 0, fn _instance -> :ok end)
      |> expect(:set_current_version_map, 0, fn _instance, _release, _attrs -> :ok end)
      |> stub(:current_version, fn _instance -> "1.0.0" end)

      Deployex.MonitorMock
      |> expect(:start_service, 1, fn _language, _instance, _deploy_ref, _options ->
        {:ok, self()}
      end)
      |> expect(:stop_service, 0, fn _instance -> :ok end)
      |> expect(:run_pre_commands, 0, fn _instance, _release, _type -> {:ok, []} end)

      Deployex.ReleaseMock
      |> expect(:download_and_unpack, 0, fn _instance, "2.0.0" ->
        {:ok, :full_deployment}
      end)
      |> stub(:get_current_version_map, fn ->
        # Leave check deployment running for a few cycles
        called = Process.get("get_current_version_map", 0)
        Process.put("get_current_version_map", called + 1)

        if called > 2 do
          send(pid, {:handle_ref_event, ref})
        end

        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 10,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Check for new version - hotupgrade - pre-commands" do
      name = "#{__MODULE__}-check-002" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> expect(:current_version, 4, fn _instance ->
        # 0 -> init
        # 1 -> check_deployment
        # 2 -> hotupgrade before upgrade
        # 3 -> after hotupgrade
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called == 3 do
          send(pid, {:handle_ref_event, ref})
          "2.0.0"
        else
          "1.0.0"
        end
      end)
      |> expect(:update, 0, fn _instance -> :ok end)
      |> expect(:set_current_version_map, 1, fn _instance, _release, _attrs -> :ok end)

      Deployex.MonitorMock
      |> expect(:start_service, 1, fn _language, _instance, _deploy_ref, _options ->
        {:ok, self()}
      end)
      |> expect(:stop_service, 0, fn _instance -> :ok end)
      |> expect(:run_pre_commands, 1, fn _instance, _release, :new -> {:ok, []} end)

      Deployex.ReleaseMock
      |> expect(:get_current_version_map, 1, fn ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> expect(:download_and_unpack, 1, fn _instance, "2.0.0" ->
        {:ok, :hot_upgrade}
      end)

      Deployex.UpgradeMock
      |> expect(:execute, 1, fn _instance, _app_lang, _app_name, "1.0.0", "2.0.0" -> :ok end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 10,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Failure on executing the hotupgrade - pre-commands" do
      name = "#{__MODULE__}-check-003" |> String.to_atom()
      ref = make_ref()
      pid = self()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _instance ->
        # keep the version unchanged, triggering full deployment
        "1.0.0"
      end)
      |> expect(:update, 1, fn _instance -> :ok end)
      |> expect(:set_current_version_map, 1, fn _instance, _release, _attrs -> :ok end)

      Deployex.MonitorMock
      |> expect(:start_service, 2, fn _language, _instance, _deploy_ref, _options ->
        # First time: initialization
        # Second time: new deployment, after hotupgrade fails
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _instance -> :ok end)
      |> stub(:run_pre_commands, fn _instance, _release, :new -> {:ok, []} end)

      Deployex.ReleaseMock
      |> stub(:get_current_version_map, fn ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> stub(:download_and_unpack, fn _instance, "2.0.0" ->
        {:ok, :hot_upgrade}
      end)

      Deployex.UpgradeMock
      |> stub(:execute, fn _instance, _app_lang, _app_name, "1.0.0", "2.0.0" ->
        {:error, "any"}
      end)

      assert capture_log(fn ->
               assert {:ok, _pid} =
                        Deployment.start_link(
                          timeout_rollback: 1_000,
                          schedule_interval: 200,
                          name: name,
                          mStatus: Deployex.StatusMock
                        )

               assert_receive {:handle_ref_event, ^ref}, 1_000
             end) =~ "Hot Upgrade failed, running for full deployment"
    end
  end

  describe "Deployment Status" do
    test "Check deployment succeed and move to the next instance" do
      name = "#{__MODULE__}-status-000" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn 1 ->
        # First 2 calls are the starting process and update
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 1 do
          "2.0.0"
        else
          "1.0.0"
        end
      end)
      |> expect(:update, 1, fn 1 -> :ok end)
      |> expect(:set_current_version_map, 1, fn _instance, _release, _attrs -> :ok end)

      Deployex.MonitorMock
      |> expect(:start_service, 2, fn _language, _instance, _deploy_ref, _options ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, 1, fn 1 -> :ok end)
      |> expect(:run_pre_commands, 0, fn _instance, _release, _type -> {:ok, []} end)

      Deployex.ReleaseMock
      |> stub(:get_current_version_map, fn ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> expect(:download_and_unpack, 1, fn 1, "2.0.0" ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 100,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000

      state = :sys.get_state(name)
      deploy_ref = state.deployments[1].deploy_ref
      Deployex.Deployment.notify_application_running(name, 1, deploy_ref)
      state = :sys.get_state(name)

      assert state.current == 2
    end

    @tag :capture_log
    test "Check deployment won't move to the next instance with invalid notification" do
      name = "#{__MODULE__}-status-001" |> String.to_atom()

      test_event_ref = make_ref()
      pid = self()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn 1 ->
        # First 2 calls are the starting process and update,
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 1 do
          "2.0.0"
        else
          "1.0.0"
        end
      end)
      |> expect(:update, 1, fn 1 -> :ok end)
      |> expect(:set_current_version_map, 1, fn _instance, _release, _attrs -> :ok end)

      Deployex.MonitorMock
      |> expect(:start_service, 2, fn _language, _instance, _deploy_ref, _options ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, test_event_ref})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, 1, fn 1 -> :ok end)
      |> expect(:run_pre_commands, 0, fn _instance, _release, _type -> {:ok, []} end)

      Deployex.ReleaseMock
      |> stub(:get_current_version_map, fn ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> expect(:download_and_unpack, 1, fn 1, "2.0.0" ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 100,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      state = :sys.get_state(name)
      deploy_ref = state.deployments[1].deploy_ref
      # Send multiple invalid data combination
      Deployex.Deployment.notify_application_running(name, 99, deploy_ref)
      Deployex.Deployment.notify_application_running(name, 1, "123456")
      Deployex.Deployment.notify_application_running(name, 99, "123456")
      state = :sys.get_state(name)

      assert state.current == 1
    end
  end

  describe "Deployment manual version" do
    test "Configure Manual version from automatic" do
      name = "#{__MODULE__}-manual-000" |> String.to_atom()

      ref = make_ref()
      pid = self()

      automatic_version = "2.0.0"
      manual_version = "1.0.0"
      manual_version_map = %{version: manual_version, hash: "local", pre_commands: []}

      Storage.config_update(%{
        Storage.config()
        | mode: :manual,
          manual_version: manual_version_map
      })

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn 1 ->
        # First time: initialization version
        # Second time: check_deployment
        # Third time: manual deployment done
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 1 do
          manual_version
        else
          automatic_version
        end
      end)
      |> expect(:update, 1, fn 1 -> :ok end)
      |> expect(:set_current_version_map, 1, fn _instance, _release, _attrs -> :ok end)

      Deployex.MonitorMock
      |> expect(:start_service, 2, fn _language, _instance, _deploy_ref, _options ->
        # First time: initialization
        # Second time: start manual version
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn 1 -> :ok end)
      |> expect(:run_pre_commands, 0, fn _instance, _release, _type -> {:ok, []} end)

      Deployex.ReleaseMock
      |> expect(:download_and_unpack, 1, fn 1, ^manual_version -> {:ok, :full_deployment} end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 30_000,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Configure Automatic version from manual" do
      name = "#{__MODULE__}-manual-001" |> String.to_atom()

      ref = make_ref()
      pid = self()

      automatic_version = "2.0.0"

      automatic_version_map = %{
        version: automatic_version,
        hash: "local",
        pre_commands: []
      }

      manual_version = "1.0.0"

      Storage.config_update(%{
        Storage.config()
        | mode: :automatic,
          manual_version: nil
      })

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn 1 ->
        # First time: initialization version
        # Second time: check_deployment
        # Third time: automatic deployment done
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 1 do
          automatic_version
        else
          manual_version
        end
      end)
      |> expect(:update, 1, fn 1 -> :ok end)
      |> expect(:set_current_version_map, 1, fn _instance, _release, _attrs -> :ok end)

      Deployex.MonitorMock
      |> expect(:start_service, 2, fn _language, _instance, _deploy_ref, _options ->
        # First time: initialization
        # Second time: start manual version
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn 1 -> :ok end)
      |> expect(:run_pre_commands, 0, fn _instance, _release, _type -> {:ok, []} end)

      Deployex.ReleaseMock
      |> expect(:download_and_unpack, 1, fn 1, ^automatic_version -> {:ok, :full_deployment} end)
      |> stub(:get_current_version_map, fn -> automatic_version_map end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 30_000,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end
  end

  describe "Deployment rollback" do
    @tag :capture_log
    test "Rollback a version after timeout" do
      name = "#{__MODULE__}-rollback-000" |> String.to_atom()

      ref = make_ref()
      pid = self()
      version_to_rollback = "1.0.0"
      version_to_ghost = "2.0.0"

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn 1 -> version_to_ghost end)
      |> expect(:update, 1, fn 1 -> :ok end)
      |> expect(:set_current_version_map, 1, fn _instance, _release, _attrs -> :ok end)
      |> expect(:current_version_map, 1, fn _instance ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:add_ghosted_version, 1, fn version_map -> {:ok, [version_map]} end)
      |> expect(:history_version_list, 1, fn _instance ->
        [
          %{version: version_to_ghost, hash: "local", pre_commands: []},
          %{version: version_to_rollback, hash: "local", pre_commands: []}
        ]
      end)

      Deployex.MonitorMock
      |> expect(:start_service, 2, fn _language, _instance, _deploy_ref, _options ->
        # First time: initialization
        # Second time: rolling back
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn 1 -> :ok end)
      |> expect(:run_pre_commands, 0, fn _instance, _release, _type -> {:ok, []} end)

      Deployex.ReleaseMock
      |> stub(:get_current_version_map, fn ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:download_and_unpack, 1, fn 1, ^version_to_rollback ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 50,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000

      state = :sys.get_state(name)
      assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
      assert state.current == 1
    end

    @tag :capture_log
    test "Rollback a version after timeout without history" do
      name = "#{__MODULE__}-rollback-001" |> String.to_atom()

      ref = make_ref()
      pid = self()
      version_to_ghost = "2.0.0"

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn 1 -> version_to_ghost end)
      |> expect(:update, 0, fn _instance -> :ok end)
      |> expect(:set_current_version_map, 0, fn _instance, _release, _attrs -> :ok end)
      |> expect(:current_version_map, 1, fn _instance ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:add_ghosted_version, 1, fn version_map -> {:ok, [version_map]} end)
      |> expect(:history_version_list, 1, fn _instance -> [] end)

      Deployex.MonitorMock
      |> expect(:start_service, 1, fn _language, _instance, _deploy_ref, _options ->
        {:ok, self()}
      end)
      |> stub(:stop_service, fn 1 -> :ok end)
      |> expect(:run_pre_commands, 0, fn _instance, _release, _type -> {:ok, []} end)

      Deployex.ReleaseMock
      |> stub(:get_current_version_map, fn ->
        # First time: initialization
        # Second time: check_deployment after rolling back signal without history
        called = Process.get("get_current_version_map", 0)
        Process.put("get_current_version_map", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:download_and_unpack, 0, fn _instance, _version_to_rollback ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 50,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000

      state = :sys.get_state(name)
      assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
      assert state.current == 1
    end

    test "Invalid rollback message" do
      name = "#{__MODULE__}-rollback-002" |> String.to_atom()

      start_service_ref = make_ref()
      running_ref = make_ref()
      pid = self()

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _instance -> "1.2.3" end)

      Deployex.MonitorMock
      |> expect(:start_service, 1, fn _language, _instance, _deploy_ref, _options ->
        send(pid, {:handle_ref_event, start_service_ref})
        {:ok, self()}
      end)

      Deployex.ReleaseMock
      |> stub(:get_current_version_map, fn ->
        # For this test, check_deployments() is expected to run
        # a couple of times after sendint the timeout_rollback
        # First time: initialization
        # Second time: first check_deployment
        # Third time: second check_deployment
        called = Process.get("get_current_version_map", 0)
        Process.put("get_current_version_map", called + 1)

        if called > 2 do
          send(pid, {:handle_ref_event, running_ref})
        end

        %Deployex.Release.Version{}
      end)

      assert {:ok, pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 100,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^start_service_ref}, 1_000

      send(pid, {:timeout_rollback, 1, make_ref()})

      assert_receive {:handle_ref_event, ^running_ref}, 1_000
    end

    @tag :capture_log
    test "Failing rolling back a version when downloading and unpacking" do
      name = "#{__MODULE__}-rollback-003" |> String.to_atom()

      ref = make_ref()
      pid = self()
      version_to_rollback = "1.0.0"
      version_to_ghost = "2.0.0"

      Deployex.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn 1 -> version_to_ghost end)
      |> expect(:update, 0, fn _instance -> :ok end)
      |> expect(:set_current_version_map, 0, fn _instance, _release, _attrs -> :ok end)
      |> expect(:current_version_map, 1, fn _instance ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:add_ghosted_version, 1, fn version_map -> {:ok, [version_map]} end)
      |> expect(:history_version_list, 1, fn _instance ->
        [
          %{version: version_to_ghost, hash: "local", pre_commands: []},
          %{version: version_to_rollback, hash: "local", pre_commands: []}
        ]
      end)

      Deployex.MonitorMock
      |> expect(:start_service, 1, fn _language, 1, _deploy_ref, _options -> {:ok, self()} end)
      |> stub(:stop_service, fn 1 -> :ok end)
      |> expect(:run_pre_commands, 0, fn _instance, _release, _type -> {:ok, []} end)

      Deployex.ReleaseMock
      |> stub(:get_current_version_map, fn ->
        # For this test, check_deployments() is expected to run
        # a couple of times after sendint the timeout_rollback
        # First time: initialization
        # Second time: first check_deployment
        # Third time: second check_deployment
        called = Process.get("get_current_version_map", 0)
        Process.put("get_current_version_map", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:download_and_unpack, 1, fn 1, ^version_to_rollback ->
        {:error, :invalid_unpack}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 50,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployex.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000

      state = :sys.get_state(name)
      assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
      assert state.current == 1
    end
  end
end
