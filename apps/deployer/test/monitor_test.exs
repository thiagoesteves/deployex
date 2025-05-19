defmodule Deployer.MonitorTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Fixture.Files, as: FixtureFiles
  alias Deployer.Monitor.Application, as: MonitorApp
  alias Foundation.Catalog
  alias Foundation.Fixture.Catalog, as: FixtureCatalog

  setup do
    FixtureCatalog.cleanup()
    name = "monitor_testapp"
    sname = Catalog.create_sname(name)

    %{
      name: name,
      sname: sname,
      port: 1000
    }
  end

  describe "Initialization tests" do
    @tag :capture_log
    test "init/1", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> expect(:current_version_map, fn ^sname ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        %Deployer.Status.Version{}
      end)

      assert {:ok, pid} = MonitorApp.start_service(sname, "elixir", port, [])

      assert Process.alive?(pid)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(sname)

      refute Process.alive?(pid)
    end

    test "Invalid sname" do
      assert %Deployer.Monitor{} = MonitorApp.state(:any)
    end

    @tag :capture_log
    test "Stop a monitor that is not running", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> expect(:current_version_map, fn ^sname ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        %Deployer.Status.Version{}
      end)

      assert {:ok, pid} = MonitorApp.start_service(sname, "elixir", port, [])

      assert Process.alive?(pid)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(sname)
      assert :ok = MonitorApp.stop_service(sname)
    end
  end

  describe "Running applications" do
    test "Running application - no executable path - elixir", %{
      sname: sname,
      port: port,
      name: name
    } do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        # Wait for at least 2 tries
        called = Process.get("current_version_map", 0)
        Process.put("current_version_map", called + 1)

        if called > 0 do
          send(test_pid_process, {:handle_ref_event, test_event_ref})
        end

        %Deployer.Status.Version{version: "1.0.0"}
      end)

      assert capture_log(fn ->
               assert {:ok, pid} =
                        MonitorApp.start_service(sname, "elixir", port,
                          retry_delay_pre_commands: 10
                        )

               assert Process.alive?(pid)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(sname)
             end) =~
               "Version: 1.0.0 set but no /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/bin/#{name}"
    end

    test "Running application - no executable path - gleam", %{
      sname: sname,
      port: port,
      name: name
    } do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        # Wait for at least 2 tries
        called = Process.get("current_version_map", 0)
        Process.put("current_version_map", called + 1)

        if called > 0 do
          send(test_pid_process, {:handle_ref_event, test_event_ref})
        end

        %Deployer.Status.Version{version: "1.0.0"}
      end)

      assert capture_log(fn ->
               assert {:ok, pid} =
                        MonitorApp.start_service(sname, "gleam", port,
                          retry_delay_pre_commands: 10
                        )

               assert Process.alive?(pid)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(sname)
             end) =~
               "Version: 1.0.0 set but no /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/erlang-shipment"
    end

    test "Running application - no executable path - erlang", %{
      sname: sname,
      port: port,
      name: name
    } do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        # Wait for at least 2 tries
        called = Process.get("current_version_map", 0)
        Process.put("current_version_map", called + 1)

        if called > 0 do
          send(test_pid_process, {:handle_ref_event, test_event_ref})
        end

        %Deployer.Status.Version{version: "1.0.0"}
      end)

      assert capture_log(fn ->
               assert {:ok, pid} =
                        MonitorApp.start_service(sname, "erlang", port,
                          retry_delay_pre_commands: 10
                        )

               assert Process.alive?(pid)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(sname)
             end) =~
               "Version: 1.0.0 set but no /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/bin/#{name}"
    end

    @tag :capture_log
    test "Running application - no pre_commands - elixir", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, fn _command, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} =
               MonitorApp.start_service(sname, "elixir", port, timeout_app_ready: 10)

      MonitorApp.subscribe_new_deploy()

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(sname)

      assert_receive {:new_deploy, _source_sname, _deploy_sname}, 1_000

      assert :ok = MonitorApp.stop_service(sname)
    end

    @tag :capture_log
    test "Running application - no pre_commands - gleam", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      language = "gleam"
      FixtureFiles.create_bin_files(language, sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, fn _command, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} =
               MonitorApp.start_service(sname, language, port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(sname)

      assert :ok = MonitorApp.stop_service(sname)
    end

    @tag :capture_log
    test "Running application - no pre_commands - erlang", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      language = "erlang"
      FixtureFiles.create_bin_files(language, sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, fn _command, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} =
               MonitorApp.start_service(sname, language, port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(sname)

      assert :ok = MonitorApp.stop_service(sname)
    end

    @tag :capture_log
    test "Running application with pre_commands - elixir", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0", pre_commands: pre_commands}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 3, fn commands, _options ->
        assert commands =~ "eval command1" or commands =~ "eval command2" or commands =~ "kill -9"
        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} =
               MonitorApp.start_service(sname, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(sname)
    end

    test "Running application with pre_commands not supported - gleam", %{
      sname: sname,
      port: port
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      language = "gleam"

      FixtureFiles.create_bin_files(language, sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0", pre_commands: pre_commands}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 3, fn commands, _options ->
        assert commands =~ "eval command1" or commands =~ "eval command2" or commands =~ "kill -9"
        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert capture_log(fn ->
               assert {:ok, _pid} =
                        MonitorApp.start_service(sname, language, port, timeout_app_ready: 10)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(sname)
             end) =~
               "Running not supported for language: #{language}, sname: #{sname}, command: eval command1"
    end

    test "Running application with pre_commands not supported - erlang", %{
      sname: sname,
      port: port
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      language = "erlang"
      FixtureFiles.create_bin_files(language, sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0", pre_commands: pre_commands}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 3, fn commands, _options ->
        assert commands =~ "eval command1" or commands =~ "eval command2" or commands =~ "kill -9"
        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert capture_log(fn ->
               assert {:ok, _pid} =
                        MonitorApp.start_service(sname, language, port, timeout_app_ready: 10)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(sname)
             end) =~
               "Running not supported for language: #{language}, sname: #{sname}, command: eval command1"
    end

    @tag :capture_log
    test "Error trying to run the application with pre-commands failing - elixir", %{
      sname: sname,
      port: port
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0", pre_commands: pre_commands}
      end)

      Host.CommanderMock
      |> expect(:run_link, 0, fn _command, _options ->
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 2, fn commands, _options ->
        if commands =~ "eval command2" do
          send(test_pid_process, {:handle_ref_event, test_event_ref})
          {:error, :command_failed}
        else
          {:ok, test_pid_process}
        end
      end)
      |> expect(:stop, 0, fn _pid -> :ok end)

      assert {:ok, _pid} = MonitorApp.start_service(sname, "elixir", port)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(sname)
    end

    @tag :capture_log
    test "Check the application doesn't change to running with invalid ref", %{
      sname: sname,
      port: port
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, fn _command, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, pid} = MonitorApp.start_service(sname, "elixir", port)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      send(pid, {:check_running, test_pid_process, sname})

      assert %{status: :starting} = Deployer.Monitor.Application.state(sname)

      assert :ok = MonitorApp.stop_service(sname)
    end

    @tag :capture_log
    test "Running pre_commands while application is running - elixir", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval running_cmd1", "eval running_cmd1"]
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 3, fn commands, _options ->
        assert commands =~ "eval running_cmd1" or commands =~ "eval running_cmd2" or
                 commands =~ "kill -9"

        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} =
               MonitorApp.start_service(sname, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(sname)

      {:ok, _pre_commands} =
        Deployer.Monitor.Application.run_pre_commands(sname, pre_commands, :new)

      assert :ok = MonitorApp.stop_service(sname)
    end

    @tag :capture_log
    test "Restart Application if EXIT message is received", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 2, fn _commands, _options ->
        Process.send_after(test_pid_process, {:handle_restart_event, test_event_ref}, 100)
        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, pid} =
               MonitorApp.start_service(sname, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running, crash_restart_count: 0} =
               Deployer.Monitor.Application.state(sname)

      send(pid, {:EXIT, test_pid_process, :forcing_restart})

      assert_receive {:handle_restart_event, ^test_event_ref}, 1_000

      # Check restart was increased
      assert %{status: :running, crash_restart_count: 1} =
               Deployer.Monitor.Application.state(sname)

      assert :ok = MonitorApp.stop_service(sname)
    end

    @tag :capture_log
    test "Don't restart Application if EXIT message is not valid", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> stub(:run, fn _commands, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, pid} =
               MonitorApp.start_service(sname, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running, crash_restart_count: 0} =
               Deployer.Monitor.Application.state(sname)

      send(pid, {:EXIT, nil, :forcing_restart})
      send(pid, {:EXIT, nil, :normal})

      # Check restart was NOT incremented
      assert %{status: :running, crash_restart_count: 0} =
               Deployer.Monitor.Application.state(sname)

      assert :ok = MonitorApp.stop_service(sname)
    end

    test "Force Restart the Application with pre-commands", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0", pre_commands: pre_commands}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 4, fn commands, _options ->
        assert commands =~ "eval command1" or commands =~ "eval command2" or commands =~ "kill -9"
        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert capture_log(fn ->
               assert {:ok, _pid} =
                        MonitorApp.start_service(sname, "elixir", port, timeout_app_ready: 10)

               assert {:error, :application_is_not_running} = MonitorApp.restart(sname)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.restart(sname)

               assert :ok = MonitorApp.stop_service(sname)
             end) =~ "Restart requested for sname: #{sname}"
    end

    test "Ignore cleanup beam command", %{sname: sname, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Deployer.Status.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 1, fn commands, _options ->
        assert commands =~ "kill -9"

        {:error, :beam_cleanup_error}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, _pid} =
               MonitorApp.start_service(sname, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(sname)

      assert :ok = MonitorApp.stop_service(sname)
    end
  end

  test "Adapter function test", %{
    sname: sname,
    port: port
  } do
    Deployer.MonitorMock
    |> expect(:start_service, fn _language, _sname, _deploy_ref, _list -> {:ok, self()} end)
    |> expect(:stop_service, fn _sname -> :ok end)
    |> expect(:state, fn _sname -> {:ok, %{}} end)
    |> expect(:restart, fn _sname -> :ok end)
    |> expect(:run_pre_commands, fn _sname, cmds, _new_or_current -> {:ok, cmds} end)
    |> expect(:global_name, fn ^sname -> %{} end)

    assert {:ok, _pid} = Deployer.Monitor.start_service(sname, "elixir", port, [])
    assert :ok = Deployer.Monitor.stop_service(sname)
    assert {:ok, %{}} = Deployer.Monitor.state(sname)
    assert :ok = Deployer.Monitor.restart(sname)
    assert {:ok, []} = Deployer.Monitor.run_pre_commands(sname, [], :new)
    assert %{} = Deployer.Monitor.global_name(sname)
  end

  @tag :capture_log
  test "Do not change state when an invalid :check_running msg is received", %{
    sname: sname,
    port: port
  } do
    test_event_ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    FixtureFiles.create_bin_files(sname)

    Deployer.StatusMock
    |> stub(:current_version_map, fn ^sname ->
      %Deployer.Status.Version{version: "1.0.0"}
    end)

    Host.CommanderMock
    |> expect(:run_link, fn _command, _options ->
      # Wait a timer greater than timeout_app_ready to guarantee app is in the
      # running state
      Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:run, fn _commands, _options ->
      {:ok, test_pid_process}
    end)
    |> stub(:stop, fn ^test_pid_process -> :ok end)

    assert {:ok, pid} =
             MonitorApp.start_service(sname, "elixir", port, timeout_app_ready: 10)

    assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

    state = Deployer.Monitor.Application.state(sname)

    send(pid, {:check_running, :any, :any})

    :timer.sleep(100)

    assert state == Deployer.Monitor.Application.state(sname)

    assert :ok = MonitorApp.stop_service(sname)
  end
end
