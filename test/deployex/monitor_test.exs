defmodule Deployex.MonitorTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.AppConfig
  alias Deployex.Fixture
  alias Deployex.Monitor.Application, as: MonitorApp

  setup do
    Fixture.storage_cleanup()
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

      create_bin_files(instance)

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

      create_bin_files(instance)

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

      create_bin_files(instance)

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

      create_bin_files(instance)

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

      create_bin_files(instance)

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

      create_bin_files(instance)

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

      assert {:ok, %{status: :running, restarts: 0}} =
               Deployex.Monitor.Application.state(instance)

      send(pid, {:EXIT, test_pid_process, :forcing_restart})

      # Check restart was increased
      assert {:ok, %{status: :running, restarts: 1}} =
               Deployex.Monitor.Application.state(instance)

      assert :ok = MonitorApp.stop_service(instance)
    end

    @tag :capture_log
    test "Don't restart Application if EXIT message is not valid" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1011
      os_pid = 123_456

      create_bin_files(instance)

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

      assert {:ok, %{status: :running, restarts: 0}} =
               Deployex.Monitor.Application.state(instance)

      send(pid, {:EXIT, nil, :forcing_restart})
      send(pid, {:EXIT, nil, :normal})

      # Check restart was NOT incremented
      assert {:ok, %{status: :running, restarts: 0}} =
               Deployex.Monitor.Application.state(instance)

      assert :ok = MonitorApp.stop_service(instance)
    end

    test "Ignore cleanup beam command" do
      ref = make_ref()
      test_pid_process = self()
      instance = 1012
      os_pid = 123_456

      create_bin_files(instance)

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

  defp create_bin_files(instance) do
    current = "#{AppConfig.current_path(instance)}/bin/"
    File.mkdir_p(current)
    File.touch!("#{current}/#{AppConfig.monitored_app()}")

    new = "#{AppConfig.new_path(instance)}/bin/"
    File.mkdir_p(new)
    File.touch!("#{new}/#{AppConfig.monitored_app()}")
  end
end
