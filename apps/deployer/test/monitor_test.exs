defmodule Deployer.MonitorTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Fixture.Binary
  alias Deployer.Fixture.Nodes, as: FixtureNodes
  alias Deployer.Monitor.Application, as: MonitorApp
  alias Foundation.Fixture.Catalog

  setup do
    Catalog.cleanup()
    name = "monitor_testapp"
    suffix = "abc123"

    %{
      name: name,
      suffix: suffix,
      node: FixtureNodes.test_node(name, suffix),
      port: 1000
    }
  end

  describe "Initialization tests" do
    @tag :capture_log
    test "init/1", %{node: node, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> expect(:current_version_map, fn ^node ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        %Deployer.Status.Version{}
      end)

      assert {:ok, pid} = MonitorApp.start_service(node, "elixir", port, [])

      assert Process.alive?(pid)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(node)

      refute Process.alive?(pid)
    end

    test "Invalid node" do
      assert %Deployer.Monitor{} = MonitorApp.state(:any)
    end

    @tag :capture_log
    test "Stop a monitor that is not running", %{node: node, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> expect(:current_version_map, fn ^node ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        %Deployer.Status.Version{}
      end)

      assert {:ok, pid} = MonitorApp.start_service(node, "elixir", port, [])

      assert Process.alive?(pid)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(node)
      assert :ok = MonitorApp.stop_service(node)
    end
  end

  describe "Running applications" do
    test "Running application - no executable path - elixir", %{
      node: node,
      port: port,
      name: name,
      suffix: suffix
    } do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
                        MonitorApp.start_service(node, "elixir", port,
                          retry_delay_pre_commands: 10
                        )

               assert Process.alive?(pid)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(node)
             end) =~
               "Version: 1.0.0 set but no /tmp/deployex/test/varlib/service/#{name}/#{name}-#{suffix}/current/bin/#{name}"
    end

    test "Running application - no executable path - gleam", %{
      node: node,
      port: port,
      name: name,
      suffix: suffix
    } do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
                        MonitorApp.start_service(node, "gleam", port,
                          retry_delay_pre_commands: 10
                        )

               assert Process.alive?(pid)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(node)
             end) =~
               "Version: 1.0.0 set but no /tmp/deployex/test/varlib/service/#{name}/#{name}-#{suffix}/current/erlang-shipment"
    end

    test "Running application - no executable path - erlang", %{
      node: node,
      port: port,
      name: name,
      suffix: suffix
    } do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
                        MonitorApp.start_service(node, "erlang", port,
                          retry_delay_pre_commands: 10
                        )

               assert Process.alive?(pid)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(node)
             end) =~
               "Version: 1.0.0 set but no /tmp/deployex/test/varlib/service/#{name}/#{name}-#{suffix}/current/bin/#{name}"
    end

    @tag :capture_log
    test "Running application - no pre_commands - elixir", %{node: node, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456

      Binary.create_bin_files(node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
               MonitorApp.start_service(node, "elixir", port, timeout_app_ready: 10)

      MonitorApp.subscribe_new_deploy()

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(node)

      assert_receive {:new_deploy, _source_node, _deploy_node}, 1_000

      assert :ok = MonitorApp.stop_service(node)
    end

    @tag :capture_log
    test "Running application - no pre_commands - gleam", %{node: node, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      language = "gleam"

      Binary.create_bin_files(language, node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
               MonitorApp.start_service(node, language, port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(node)

      assert :ok = MonitorApp.stop_service(node)
    end

    @tag :capture_log
    test "Running application - no pre_commands - erlang", %{node: node, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      language = "erlang"

      Binary.create_bin_files(language, node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
               MonitorApp.start_service(node, language, port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(node)

      assert :ok = MonitorApp.stop_service(node)
    end

    @tag :capture_log
    test "Running application with pre_commands - elixir", %{node: node, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]

      Binary.create_bin_files(node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
               MonitorApp.start_service(node, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(node)
    end

    test "Running application with pre_commands not supported - gleam", %{node: node, port: port} do
      test_event_ref = make_ref()

      test_pid_process = self()

      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      language = "gleam"

      Binary.create_bin_files(language, node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
                        MonitorApp.start_service(node, language, port, timeout_app_ready: 10)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(node)
             end) =~
               "Running not supported for language: #{language}, node: #{node}, command: eval command1"
    end

    test "Running application with pre_commands not supported - erlang", %{node: node, port: port} do
      test_event_ref = make_ref()

      test_pid_process = self()

      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      language = "erlang"

      Binary.create_bin_files(language, node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
                        MonitorApp.start_service(node, language, port, timeout_app_ready: 10)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(node)
             end) =~
               "Running not supported for language: #{language}, node: #{node}, command: eval command1"
    end

    @tag :capture_log
    test "Error trying to run the application with pre-commands failing - elixir", %{
      node: node,
      port: port
    } do
      test_event_ref = make_ref()

      test_pid_process = self()

      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]

      Binary.create_bin_files(node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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

      assert {:ok, _pid} = MonitorApp.start_service(node, "elixir", port)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(node)
    end

    @tag :capture_log
    test "Check the application doesn't change to running with invalid ref", %{
      node: node,
      port: port
    } do
      test_event_ref = make_ref()

      test_pid_process = self()

      os_pid = 123_456

      Binary.create_bin_files(node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
        %Deployer.Status.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, fn _command, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, pid} = MonitorApp.start_service(node, "elixir", port)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      send(pid, {:check_running, test_pid_process, node})

      assert %{status: :starting} = Deployer.Monitor.Application.state(node)

      assert :ok = MonitorApp.stop_service(node)
    end

    @tag :capture_log
    test "Running pre_commands while application is running - elixir", %{node: node, port: port} do
      test_event_ref = make_ref()

      test_pid_process = self()

      os_pid = 123_456
      pre_commands = ["eval running_cmd1", "eval running_cmd1"]

      Binary.create_bin_files(node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
               MonitorApp.start_service(node, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(node)

      {:ok, _pre_commands} =
        Deployer.Monitor.Application.run_pre_commands(node, pre_commands, :new)

      assert :ok = MonitorApp.stop_service(node)
    end

    @tag :capture_log
    test "Restart Application if EXIT message is received", %{node: node, port: port} do
      test_event_ref = make_ref()

      test_pid_process = self()

      os_pid = 123_456

      Binary.create_bin_files(node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
               MonitorApp.start_service(node, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running, crash_restart_count: 0} =
               Deployer.Monitor.Application.state(node)

      send(pid, {:EXIT, test_pid_process, :forcing_restart})

      assert_receive {:handle_restart_event, ^test_event_ref}, 1_000

      # Check restart was increased
      assert %{status: :running, crash_restart_count: 1} =
               Deployer.Monitor.Application.state(node)

      assert :ok = MonitorApp.stop_service(node)
    end

    @tag :capture_log
    test "Don't restart Application if EXIT message is not valid", %{node: node, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456

      Binary.create_bin_files(node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
               MonitorApp.start_service(node, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running, crash_restart_count: 0} =
               Deployer.Monitor.Application.state(node)

      send(pid, {:EXIT, nil, :forcing_restart})
      send(pid, {:EXIT, nil, :normal})

      # Check restart was NOT incremented
      assert %{status: :running, crash_restart_count: 0} =
               Deployer.Monitor.Application.state(node)

      assert :ok = MonitorApp.stop_service(node)
    end

    test "Force Restart the Application with pre-commands", %{node: node, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]

      Binary.create_bin_files(node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
                        MonitorApp.start_service(node, "elixir", port, timeout_app_ready: 10)

               assert {:error, :application_is_not_running} = MonitorApp.restart(node)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.restart(node)

               assert :ok = MonitorApp.stop_service(node)
             end) =~ "Restart requested for node: #{node}"
    end

    test "Ignore cleanup beam command", %{node: node, port: port} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456

      Binary.create_bin_files(node)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^node ->
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
               MonitorApp.start_service(node, "elixir", port, timeout_app_ready: 10)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = Deployer.Monitor.Application.state(node)

      assert :ok = MonitorApp.stop_service(node)
    end
  end

  test "Adapter function test", %{
    node: node,
    port: port
  } do
    Deployer.MonitorMock
    |> expect(:start_service, fn _language, _node, _deploy_ref, _list -> {:ok, self()} end)
    |> expect(:stop_service, fn _node -> :ok end)
    |> expect(:state, fn _node -> {:ok, %{}} end)
    |> expect(:restart, fn _node -> :ok end)
    |> expect(:run_pre_commands, fn _node, cmds, _new_or_current -> {:ok, cmds} end)
    |> expect(:global_name, fn ^node -> %{} end)

    assert {:ok, _pid} = Deployer.Monitor.start_service(node, "elixir", port, [])
    assert :ok = Deployer.Monitor.stop_service(node)
    assert {:ok, %{}} = Deployer.Monitor.state(node)
    assert :ok = Deployer.Monitor.restart(node)
    assert {:ok, []} = Deployer.Monitor.run_pre_commands(node, [], :new)
    assert %{} = Deployer.Monitor.global_name(node)
  end

  @tag :capture_log
  test "Do not change state when an invalid :check_running msg is received", %{
    node: node,
    port: port
  } do
    test_event_ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Binary.create_bin_files(node)

    Deployer.StatusMock
    |> stub(:current_version_map, fn ^node ->
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
             MonitorApp.start_service(node, "elixir", port, timeout_app_ready: 10)

    assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

    state = Deployer.Monitor.Application.state(node)

    send(pid, {:check_running, :any, :any})

    :timer.sleep(100)

    assert state == Deployer.Monitor.Application.state(node)

    assert :ok = MonitorApp.stop_service(node)
  end
end
