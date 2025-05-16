defmodule Deployer.DeploymentTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Deployment
  alias Foundation.Catalog
  alias Foundation.Common
  alias Foundation.Fixture.Catalog, as: FixtureCatalog

  setup do
    FixtureCatalog.cleanup()
  end

  describe "Initialization tests" do
    test "init/1" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      Deployer.StatusMock
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
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node ->
        Process.send_after(pid, {:handle_ref_event, ref}, 100)
        nil
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name -> nil end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 10,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Initialization with version configured" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> expect(:current_version, fn _node -> "1.2.3" end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _node, _language, _port, _options ->
        send(pid, {:handle_ref_event, ref})
        {:ok, self()}
      end)

      Deployer.ReleaseMock
      |> expect(:download_version_map, 0, fn _app_name -> nil end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 10,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end
  end

  describe "Checking deployment" do
    test "Check for new version - full deployment - no pre-commands" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> expect(:current_version, 2, fn _node -> "1.0.0" end)
      |> expect(:update, 1, fn _node -> :ok end)
      |> expect(:set_current_version_map, 1, fn _node, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _node, _language, _port, _options ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, 1, fn _node -> :ok end)
      |> expect(:run_pre_commands, 0, fn _node, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> expect(:download_version_map, 1, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, 1, fn _app_name, "2.0.0", _download_path ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 10,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Check for new version - ignore ghosted version" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [%{version: "2.0.0"}] end)
      |> expect(:update, 0, fn _node -> :ok end)
      |> expect(:set_current_version_map, 0, fn _node, _release, _attrs -> :ok end)
      |> stub(:current_version, fn _node -> "1.0.0" end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _node, _language, _port, _options ->
        {:ok, self()}
      end)
      |> expect(:stop_service, 0, fn _node -> :ok end)
      |> expect(:run_pre_commands, 0, fn _node, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> expect(:download_release, 0, fn _app_name, "2.0.0", _download_path ->
        {:ok, :full_deployment}
      end)
      |> stub(:download_version_map, fn _app_name ->
        # Leave check deployment running for a few cycles
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

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
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Check for new version - hotupgrade - pre-commands" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> expect(:current_version, 4, fn _node ->
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
      |> expect(:update, 0, fn _node -> :ok end)
      |> expect(:set_current_version_map, 1, fn _node, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _node, _language, _port, _options ->
        {:ok, self()}
      end)
      |> expect(:stop_service, 0, fn _node -> :ok end)
      |> expect(:run_pre_commands, 1, fn _node, _release, :new -> {:ok, []} end)

      Deployer.ReleaseMock
      |> expect(:download_version_map, 1, fn _app_name ->
        %{"version" => "2.0.0", "hash" => "local", "pre_commands" => []}
      end)
      |> expect(:download_release, 1, fn _app_name, "2.0.0", _download_path ->
        {:ok, :hot_upgrade}
      end)

      Deployer.UpgradeMock
      |> expect(:execute, 1, fn _node, _app_name, _app_lang, "1.0.0", "2.0.0" -> :ok end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 10,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Failure on executing the hotupgrade - pre-commands" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node ->
        # keep the version unchanged, triggering full deployment
        "1.0.0"
      end)
      |> expect(:update, 1, fn _node -> :ok end)
      |> expect(:set_current_version_map, 1, fn _node, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _node, _language, _port, _options ->
        # First time: initialization
        # Second time: new deployment, after hotupgrade fails
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _node -> :ok end)
      |> stub(:run_pre_commands, fn _node, _release, :new -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> stub(:download_release, fn _app_name, "2.0.0", _download_path ->
        {:ok, :hot_upgrade}
      end)

      Deployer.UpgradeMock
      |> stub(:execute, fn _node, _app_name, _app_lang, "1.0.0", "2.0.0" ->
        {:error, "any"}
      end)

      assert capture_log(fn ->
               assert {:ok, _pid} =
                        Deployment.start_link(
                          timeout_rollback: 1_000,
                          schedule_interval: 200,
                          name: name,
                          mStatus: Deployer.StatusMock
                        )

               assert_receive {:handle_ref_event, ^ref}, 1_000
             end) =~ "Hot Upgrade failed, running for full deployment"
    end
  end

  describe "Deployment Status" do
    test "Check deployment succeed and move to the next instance" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node ->
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
      |> expect(:update, 1, fn _node -> :ok end)
      |> expect(:set_current_version_map, 1, fn _node, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn node, _language, _port, _options ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref, node})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, 1, fn _node -> :ok end)
      |> expect(:run_pre_commands, 0, fn _node, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, 1, fn _app_name, "2.0.0", _download_path ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 100,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref, node}, 1_000

      _state = :sys.get_state(name)
      Deployment.notify_application_running(name, node)
      state = :sys.get_state(name)

      assert state.current == 2
    end

    @tag :capture_log
    test "Check deployment won't move to the next instance with invalid notification" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      test_event_ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node ->
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
      |> expect(:update, 1, fn _node -> :ok end)
      |> expect(:set_current_version_map, 1, fn _node, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _node, _language, _port, _options ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, test_event_ref})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, 1, fn _node -> :ok end)
      |> expect(:run_pre_commands, 0, fn _node, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, 1, fn _app_name, "2.0.0", _download_path ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 100,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      _state = :sys.get_state(name)
      # Send multiple invalid data combination
      Deployment.notify_application_running(name, 99)
      Deployment.notify_application_running(name, 1)
      Deployment.notify_application_running(name, 99)
      state = :sys.get_state(name)

      assert state.current == 1
    end
  end

  describe "Deployment manual version" do
    test "Configure Manual version from automatic" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()

      automatic_version = "2.0.0"
      manual_version = "1.0.0"
      manual_version_map = %{version: manual_version, hash: "local", pre_commands: []}

      Catalog.config_update(%{
        Catalog.config()
        | mode: :manual,
          manual_version: manual_version_map
      })

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node ->
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
      |> expect(:update, 1, fn _node -> :ok end)
      |> expect(:set_current_version_map, 1, fn _node, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _node, _language, _port, _options ->
        # First time: initialization
        # Second time: start manual version
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _node -> :ok end)
      |> expect(:run_pre_commands, 0, fn _node, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> expect(:download_release, 1, fn _app_name, ^manual_version, _version_to_rollback ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 30_000,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Configure Automatic version from manual" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()

      automatic_version = "2.0.0"

      automatic_version_map = %{
        version: automatic_version,
        hash: "local",
        pre_commands: []
      }

      manual_version = "1.0.0"

      Catalog.config_update(%{
        Catalog.config()
        | mode: :automatic,
          manual_version: nil
      })

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node ->
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
      |> expect(:update, 1, fn _node -> :ok end)
      |> expect(:set_current_version_map, 1, fn _node, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _node, _language, _port, _options ->
        # First time: initialization
        # Second time: start manual version
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _node -> :ok end)
      |> expect(:run_pre_commands, 0, fn _node, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> expect(:download_release, 1, fn _app_name, ^automatic_version, _download_path ->
        {:ok, :full_deployment}
      end)
      |> stub(:download_version_map, fn _app_name -> automatic_version_map end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 30_000,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end
  end

  describe "Deployment rollback" do
    @tag :capture_log
    test "Rollback a version after timeout" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()
      version_to_rollback = "1.0.0"
      version_to_ghost = "2.0.0"

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node -> version_to_ghost end)
      |> expect(:update, 1, fn _node -> :ok end)
      |> expect(:set_current_version_map, 1, fn _node, _release, _attrs -> :ok end)
      |> expect(:current_version_map, 1, fn _node ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:add_ghosted_version, 1, fn version_map -> {:ok, [version_map]} end)
      |> expect(:history_version_list, 1, fn _node ->
        [
          %{version: version_to_ghost, hash: "local", pre_commands: []},
          %{version: version_to_rollback, hash: "local", pre_commands: []}
        ]
      end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _node, _language, _port, _options ->
        # First time: initialization
        # Second time: rolling back
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _node -> :ok end)
      |> expect(:run_pre_commands, 0, fn _node, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, 1, fn _app_name, ^version_to_rollback, _download_path ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 50,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000

      state = :sys.get_state(name)
      assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
      assert state.current == 1
    end

    @tag :capture_log
    test "Rollback a version after timeout without history" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()
      version_to_ghost = "2.0.0"

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node -> version_to_ghost end)
      |> expect(:update, 0, fn _node -> :ok end)
      |> expect(:set_current_version_map, 0, fn _node, _release, _attrs -> :ok end)
      |> expect(:current_version_map, 1, fn _node ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:add_ghosted_version, 1, fn version_map -> {:ok, [version_map]} end)
      |> expect(:history_version_list, 1, fn _node -> [] end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _node, _language, _port, _options ->
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _node -> :ok end)
      |> expect(:run_pre_commands, 0, fn _node, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: check_deployment after rolling back signal without history
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, 0, fn _app_name, _release_version, _version_to_rollback ->
        {:ok, :full_deployment}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 50,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000

      state = :sys.get_state(name)
      assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
      assert state.current == 1
    end

    test "Invalid rollback message" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      start_service_ref = make_ref()
      running_ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node -> "1.2.3" end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _node, _language, _port, _options ->
        send(pid, {:handle_ref_event, start_service_ref})
        {:ok, self()}
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # For this test, check_deployments() is expected to run
        # a couple of times after sendint the timeout_rollback
        # First time: initialization
        # Second time: first check_deployment
        # Third time: second check_deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 2 do
          send(pid, {:handle_ref_event, running_ref})
        end

        %Deployer.Release.Version{}
      end)

      assert {:ok, pid} =
               Deployment.start_link(
                 timeout_rollback: 1_000,
                 schedule_interval: 100,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^start_service_ref}, 1_000

      send(pid, {:timeout_rollback, 1, make_ref()})

      assert_receive {:handle_ref_event, ^running_ref}, 1_000
    end

    @tag :capture_log
    test "Failing rolling back a version when downloading and unpacking" do
      name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

      ref = make_ref()
      pid = self()
      version_to_rollback = "1.0.0"
      version_to_ghost = "2.0.0"

      Deployer.StatusMock
      |> expect(:ghosted_version_list, fn -> [] end)
      |> stub(:current_version, fn _node -> version_to_ghost end)
      |> expect(:update, 0, fn _node -> :ok end)
      |> expect(:set_current_version_map, 0, fn _node, _release, _attrs -> :ok end)
      |> expect(:current_version_map, 1, fn _node ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:add_ghosted_version, 1, fn version_map -> {:ok, [version_map]} end)
      |> expect(:history_version_list, 1, fn _node ->
        [
          %{version: version_to_ghost, hash: "local", pre_commands: []},
          %{version: version_to_rollback, hash: "local", pre_commands: []}
        ]
      end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _node, _language, _port, _options -> {:ok, self()} end)
      |> stub(:stop_service, fn _node -> :ok end)
      |> expect(:run_pre_commands, 0, fn _node, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # For this test, check_deployments() is expected to run
        # a couple of times after sendint the timeout_rollback
        # First time: initialization
        # Second time: first check_deployment
        # Third time: second check_deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, 1, fn _app_name, ^version_to_rollback, _download_path ->
        {:error, :invalid_unpack}
      end)

      assert {:ok, _pid} =
               Deployment.start_link(
                 timeout_rollback: 50,
                 schedule_interval: 200,
                 name: name,
                 mStatus: Deployer.StatusMock
               )

      assert_receive {:handle_ref_event, ^ref}, 1_000

      state = :sys.get_state(name)
      assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
      assert state.current == 1
    end
  end
end
