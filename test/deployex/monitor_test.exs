defmodule Deployex.MonitorTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.Fixture.Binary
  alias Deployex.Fixture.Storage
  alias Deployex.Monitor.Application, as: MonitorApp

  setup do
    Storage.cleanup()
  end

  describe "Initialization tests" do
    @tag :capture_log
    test "init/1" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1000

      Deployex.StatusMock
      |> expect(:current_version_map, fn ^instance ->
        send(test_pid_process, {:handle_ref_event, ref})
        nil
      end)

      assert {:ok, pid} = MonitorApp.start_service(instance, ref)

      assert Process.alive?(pid)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert :ok = MonitorApp.stop_service(instance)

      refute Process.alive?(pid)
    end

    @tag :capture_log
    test "Stop a monitor that is not running" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1001

      Deployex.StatusMock
      |> expect(:current_version_map, fn ^instance ->
        send(test_pid_process, {:handle_ref_event, ref})
        nil
      end)

      assert {:ok, pid} = MonitorApp.start_service(instance, ref)

      assert Process.alive?(pid)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert :ok = MonitorApp.stop_service(instance)
      assert :ok = MonitorApp.stop_service(instance)
    end
  end

  describe "Running applications" do
    @tag :capture_log
    test "Running application - no executable path" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1002

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        # Wait for at least 2 tries
        called = Process.get("current_version_map", 0)
        Process.put("current_version_map", called + 1)

        if called > 0 do
          send(test_pid_process, {:handle_ref_event, ref})
        end

        %{
          "version" => "1.0.0",
          "pre_commands" => []
        }
      end)

      assert {:ok, pid} = MonitorApp.start_service(instance, ref, retry_delay_pre_commands: 10)

      assert Process.alive?(pid)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert :ok = MonitorApp.stop_service(instance)
    end

    @tag :capture_log
    test "Running application - no pre_commands" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1003
      os_pid = 123_456

      Binary.create_bin_files(instance)

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        %{
          "version" => "1.0.0",
          "pre_commands" => []
        }
      end)

      Deployex.OpSysMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, fn _command, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} = MonitorApp.start_service(instance, ref, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert {:ok, %{status: :running}} = Deployex.Monitor.Application.state(instance)

      assert :ok = MonitorApp.stop_service(instance)
    end

    @tag :capture_log
    test "Running application with pre_commands" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1004
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]

      Binary.create_bin_files(instance)

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        %{
          "version" => "1.0.0",
          "pre_commands" => pre_commands
        }
      end)

      Deployex.OpSysMock
      |> expect(:run_link, fn _command, _options ->
        send(test_pid_process, {:handle_ref_event, ref})
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 3, fn commands, _options ->
        assert commands =~ "eval command1" or commands =~ "eval command2" or commands =~ "kill -9"
        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} = MonitorApp.start_service(instance, ref, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert :ok = MonitorApp.stop_service(instance)
    end

    @tag :capture_log
    test "Error trying to run the application with pre-commands failing" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1005
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]

      Binary.create_bin_files(instance)

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        %{
          "version" => "1.0.0",
          "pre_commands" => pre_commands
        }
      end)

      Deployex.OpSysMock
      |> expect(:run_link, 0, fn _command, _options ->
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 2, fn commands, _options ->
        if commands =~ "eval command2" do
          send(test_pid_process, {:handle_ref_event, ref})
          {:error, :command_failed}
        else
          {:ok, test_pid_process}
        end
      end)
      |> expect(:stop, 0, fn _pid -> :ok end)

      assert {:ok, _pid} = MonitorApp.start_service(instance, ref)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert :ok = MonitorApp.stop_service(instance)
    end

    @tag :capture_log
    test "Check the application doesn't change to running with invalid ref" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1006
      os_pid = 123_456

      Binary.create_bin_files(instance)

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        %{
          "version" => "1.0.0",
          "pre_commands" => []
        }
      end)

      Deployex.OpSysMock
      |> expect(:run_link, fn _command, _options ->
        send(test_pid_process, {:handle_ref_event, ref})
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, fn _command, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, pid} = MonitorApp.start_service(instance, ref)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      send(pid, {:check_running, test_pid_process, make_ref()})

      assert {:ok, %{status: :starting}} = Deployex.Monitor.Application.state(instance)

      assert :ok = MonitorApp.stop_service(instance)
    end

    @tag :capture_log
    test "Running pre_commands while application is running" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1009
      os_pid = 123_456
      pre_commands = ["eval running_cmd1", "eval running_cmd1"]

      Binary.create_bin_files(instance)

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        %{
          "version" => "1.0.0",
          "pre_commands" => []
        }
      end)

      Deployex.OpSysMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 3, fn commands, _options ->
        assert commands =~ "eval running_cmd1" or commands =~ "eval running_cmd2" or
                 commands =~ "kill -9"

        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} = MonitorApp.start_service(instance, ref, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert {:ok, %{status: :running}} = Deployex.Monitor.Application.state(instance)

      {:ok, _pre_commands} =
        Deployex.Monitor.Application.run_pre_commands(instance, pre_commands, :new)

      assert :ok = MonitorApp.stop_service(instance)
    end

    @tag :capture_log
    test "Restart Application if EXIT message is received" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1010
      os_pid = 123_456

      Binary.create_bin_files(instance)

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        %{
          "version" => "1.0.0",
          "pre_commands" => []
        }
      end)

      Deployex.OpSysMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> stub(:run, fn _commands, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, pid} = MonitorApp.start_service(instance, ref, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert {:ok, %{status: :running, crash_restart_count: 0}} =
               Deployex.Monitor.Application.state(instance)

      send(pid, {:EXIT, test_pid_process, :forcing_restart})

      # Check restart was increased
      assert {:ok, %{status: :running, crash_restart_count: 1}} =
               Deployex.Monitor.Application.state(instance)

      assert :ok = MonitorApp.stop_service(instance)
    end

    @tag :capture_log
    test "Don't restart Application if EXIT message is not valid" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1011
      os_pid = 123_456

      Binary.create_bin_files(instance)

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        %{
          "version" => "1.0.0",
          "pre_commands" => []
        }
      end)

      Deployex.OpSysMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> stub(:run, fn _commands, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, pid} = MonitorApp.start_service(instance, ref, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert {:ok, %{status: :running, crash_restart_count: 0}} =
               Deployex.Monitor.Application.state(instance)

      send(pid, {:EXIT, nil, :forcing_restart})
      send(pid, {:EXIT, nil, :normal})

      # Check restart was NOT incremented
      assert {:ok, %{status: :running, crash_restart_count: 0}} =
               Deployex.Monitor.Application.state(instance)

      assert :ok = MonitorApp.stop_service(instance)
    end

    test "Force Restart the Application with pre-commands" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1012
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]

      Binary.create_bin_files(instance)

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        %{
          "version" => "1.0.0",
          "pre_commands" => pre_commands
        }
      end)

      Deployex.OpSysMock
      |> expect(:run_link, fn _command, _options ->
        send(test_pid_process, {:handle_ref_event, ref})
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 4, fn commands, _options ->
        assert commands =~ "eval command1" or commands =~ "eval command2" or commands =~ "kill -9"
        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert capture_log(fn ->
               assert {:ok, _pid} = MonitorApp.start_service(instance, ref, timeout_app_ready: 10)

               assert {:error, :application_is_not_running} = MonitorApp.restart(instance)

               assert_receive {:handle_ref_event, ^ref}, 1_000

               assert :ok = MonitorApp.restart(instance)

               assert :ok = MonitorApp.stop_service(instance)
             end) =~ "Restart requested for instance: #{instance}"
    end

    test "Ignore cleanup beam command" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1013
      os_pid = 123_456

      Binary.create_bin_files(instance)

      Deployex.StatusMock
      |> stub(:current_version_map, fn ^instance ->
        %{
          "version" => "1.0.0",
          "pre_commands" => []
        }
      end)

      Deployex.OpSysMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 1, fn commands, _options ->
        assert commands =~ "kill -9"

        {:error, :beam_cleanup_error}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} = MonitorApp.start_service(instance, ref, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^ref}, 1_000

      assert {:ok, %{status: :running}} = Deployex.Monitor.Application.state(instance)

      assert :ok = MonitorApp.stop_service(instance)
    end
  end

  test "Adapter function test" do
    Deployex.MonitorMock
    |> expect(:start_service, fn _instance, _reference, _list -> {:ok, self()} end)
    |> expect(:stop_service, fn _instance -> :ok end)
    |> expect(:state, fn _instance -> {:ok, %{}} end)
    |> expect(:restart, fn _instance -> :ok end)
    |> expect(:run_pre_commands, fn _instance, cmds, _new_or_current -> {:ok, cmds} end)
    |> expect(:global_name, fn _instance -> %{} end)

    assert {:ok, _pid} = Deployex.Monitor.start_service(1, make_ref(), [])
    assert :ok = Deployex.Monitor.stop_service(1)
    assert {:ok, %{}} = Deployex.Monitor.state(1)
    assert :ok = Deployex.Monitor.restart(1)
    assert {:ok, []} = Deployex.Monitor.run_pre_commands(1, [], :new)
    assert %{} = Deployex.Monitor.global_name(1)
  end
end
