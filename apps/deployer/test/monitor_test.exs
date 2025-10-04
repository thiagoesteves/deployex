defmodule Deployer.MonitorTest do
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Fixture.Files, as: FixtureFiles
  alias Deployer.Monitor.Application, as: MonitorApp
  alias Deployer.Monitor.Service
  alias Foundation.Catalog
  alias Foundation.Fixture.Catalog, as: FixtureCatalog

  setup do
    FixtureCatalog.cleanup()
    name = "myelixir"
    sname = Catalog.create_sname(name)

    gleam_name = "mygleam"
    gleam_sname = Catalog.create_sname(gleam_name)

    erlang_name = "myerlang"
    erlang_sname = Catalog.create_sname(erlang_name)

    # Note: Monitors are Created by Engines, which assigns
    #       names as atoms
    _atom = String.to_atom(name)
    _atom = String.to_atom(gleam_name)
    _atom = String.to_atom(erlang_name)

    %{
      elixir_name: name,
      elixir_sname: sname,
      gleam_name: gleam_name,
      gleam_sname: gleam_sname,
      erlang_name: erlang_name,
      erlang_sname: erlang_sname,
      ports: [%{key: "PORT", base: 1000}]
    }
  end

  describe "Initialization tests" do
    @tag :capture_log
    test "init/1", %{elixir_name: name, elixir_sname: sname, ports: ports} do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> expect(:current_version_map, fn ^sname ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        %Catalog.Version{}
      end)

      assert {:ok, pid} =
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports
               })

      assert Process.alive?(pid)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(name, sname)

      refute Process.alive?(pid)
    end

    test "Invalid sname" do
      assert %Deployer.Monitor{} = MonitorApp.state(:any)
    end

    @tag :capture_log
    test "Stop a monitor that is not running", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()

      Deployer.StatusMock
      |> expect(:current_version_map, fn ^sname ->
        send(test_pid_process, {:handle_ref_event, test_event_ref})
        %Catalog.Version{}
      end)

      assert {:ok, pid} =
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports
               })

      assert Process.alive?(pid)

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(name, sname)
      assert :ok = MonitorApp.stop_service(name, sname)
    end
  end

  describe "Running applications" do
    test "Running application - no executable path - elixir", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
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

        %Catalog.Version{version: "1.0.0"}
      end)

      assert capture_log(fn ->
               assert {:ok, pid} =
                        MonitorApp.start_service(%Service{
                          name: name,
                          sname: sname,
                          language: "elixir",
                          ports: ports,
                          retry_delay_pre_commands: 10
                        })

               assert Process.alive?(pid)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(name, sname)
             end) =~
               "Version: 1.0.0 set but no /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/bin/#{name}"
    end

    test "Running application - no executable path - gleam", %{
      gleam_name: name,
      gleam_sname: sname,
      ports: ports
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

        %Catalog.Version{version: "1.0.0", name: name, sname: sname}
      end)

      assert capture_log(fn ->
               assert {:ok, pid} =
                        MonitorApp.start_service(%Service{
                          name: name,
                          sname: sname,
                          language: "gleam",
                          ports: ports,
                          retry_delay_pre_commands: 10
                        })

               assert Process.alive?(pid)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(name, sname)
             end) =~
               "Version: 1.0.0 set but no /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/erlang-shipment"
    end

    test "Running application - no executable path - erlang", %{
      erlang_name: name,
      erlang_sname: sname,
      ports: ports
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

        %Catalog.Version{version: "1.0.0", sname: sname, name: name}
      end)

      assert capture_log(fn ->
               assert {:ok, pid} =
                        MonitorApp.start_service(%Service{
                          name: name,
                          sname: sname,
                          language: "erlang",
                          ports: ports,
                          retry_delay_pre_commands: 10
                        })

               assert Process.alive?(pid)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(name, sname)
             end) =~
               "Version: 1.0.0 set but no /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/bin/#{name}"
    end

    @tag :capture_log
    test "Running application - no pre_commands - elixir", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0"}
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
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports,
                 timeout_app_ready: 10
               })

      MonitorApp.subscribe_new_deploy()

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = MonitorApp.state(sname)

      assert_receive {:new_deploy, _source_sname, _deploy_sname}, 1_000

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    @tag :capture_log
    test "Running application - no pre_commands - gleam", %{
      gleam_sname: sname,
      gleam_name: name,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      language = "gleam"
      FixtureFiles.create_bin_files(language, sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0", sname: sname, name: name}
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
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: language,
                 ports: ports,
                 timeout_app_ready: 10
               })

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = MonitorApp.state(sname)

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    @tag :capture_log
    test "Running application - no pre_commands - erlang", %{
      erlang_sname: sname,
      erlang_name: name,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      language = "erlang"
      FixtureFiles.create_bin_files(language, sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0", sname: sname, name: name}
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
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: language,
                 ports: ports,
                 timeout_app_ready: 10
               })

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = MonitorApp.state(sname)

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    @tag :capture_log
    test "Running application with pre_commands - elixir", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0", pre_commands: pre_commands}
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
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports,
                 timeout_app_ready: 10
               })

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    test "Running application with pre_commands not supported - gleam", %{
      gleam_name: name,
      gleam_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      language = "gleam"

      FixtureFiles.create_bin_files(language, sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0", pre_commands: pre_commands, sname: sname, name: name}
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
                        MonitorApp.start_service(%Service{
                          name: name,
                          sname: sname,
                          language: language,
                          ports: ports,
                          timeout_app_ready: 10
                        })

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(name, sname)
             end) =~
               "Running not supported for language: #{language}, sname: #{sname}, command: eval command1"
    end

    test "Running application with pre_commands not supported - erlang", %{
      erlang_name: name,
      erlang_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      language = "erlang"
      FixtureFiles.create_bin_files(language, sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0", pre_commands: pre_commands, sname: sname, name: name}
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
                        MonitorApp.start_service(%Service{
                          name: name,
                          sname: sname,
                          language: language,
                          ports: ports,
                          timeout_app_ready: 10
                        })

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.stop_service(name, sname)
             end) =~
               "Running not supported for language: #{language}, sname: #{sname}, command: eval command1"
    end

    @tag :capture_log
    test "Error trying to run the application with pre-commands failing - elixir", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0", pre_commands: pre_commands}
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

      assert {:ok, _pid} =
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports
               })

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    @tag :capture_log
    test "Check the application doesn't change to running with invalid ref", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, fn _command, _options -> {:ok, test_pid_process} end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, pid} =
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports
               })

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      send(pid, {:check_running, test_pid_process, sname})

      assert %{status: :starting} = MonitorApp.state(sname)

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    @tag :capture_log
    test "Running pre_commands while application is running - elixir", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval running_cmd1", "eval running_cmd1"]
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0"}
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
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports,
                 timeout_app_ready: 10
               })

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = MonitorApp.state(sname)

      {:ok, _pre_commands} = MonitorApp.run_pre_commands(sname, pre_commands, :new)

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    @tag :capture_log
    test "Restart Application if EXIT message is received", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        # Wait a timer greater than timeout_app_ready to guarantee app is in the
        # running state
        Process.send_after(test_pid_process, {:handle_ref_event, test_event_ref}, 100)
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:run, 1, fn _commands, _options ->
        Process.send_after(test_pid_process, {:handle_restart_event, test_event_ref}, 100)
        {:ok, test_pid_process}
      end)
      |> stub(:stop, fn ^test_pid_process -> :ok end)

      assert {:ok, pid} =
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports,
                 timeout_app_ready: 10
               })

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running, crash_restart_count: 0} = MonitorApp.state(sname)

      send(pid, {:EXIT, test_pid_process, :forcing_restart})

      assert_receive {:handle_restart_event, ^test_event_ref}, 1_000

      # Check restart was increased
      assert %{status: :running, crash_restart_count: 1} = MonitorApp.state(sname)

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    @tag :capture_log
    test "Don't restart Application if EXIT message is not valid", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0"}
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
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports,
                 timeout_app_ready: 10
               })

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running, crash_restart_count: 0} = MonitorApp.state(sname)

      send(pid, {:EXIT, nil, :forcing_restart})
      send(pid, {:EXIT, nil, :normal})

      # Check restart was NOT incremented
      assert %{status: :running, crash_restart_count: 0} = MonitorApp.state(sname)

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    test "Force Restart the Application with pre-commands", %{
      elixir_name: name,
      elixir_sname: sname,
      ports: ports
    } do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      pre_commands = ["eval command1", "eval command2"]
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0", pre_commands: pre_commands}
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
                        MonitorApp.start_service(%Service{
                          name: name,
                          sname: sname,
                          language: "elixir",
                          ports: ports,
                          timeout_app_ready: 10
                        })

               assert {:error, :application_is_not_running} = MonitorApp.restart(sname)

               assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

               assert :ok = MonitorApp.restart(sname)

               assert :ok = MonitorApp.stop_service(name, sname)
             end) =~ "Restart requested for sname: #{sname}"
    end

    test "Ignore cleanup beam command", %{elixir_name: name, elixir_sname: sname, ports: ports} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0"}
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
               MonitorApp.start_service(%Service{
                 name: name,
                 sname: sname,
                 language: "elixir",
                 ports: ports,
                 timeout_app_ready: 10
               })

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert %{status: :running} = MonitorApp.state(sname)

      assert :ok = MonitorApp.stop_service(name, sname)
    end
  end

  test "Adapter function test", %{
    elixir_name: name,
    elixir_sname: sname,
    ports: ports
  } do
    Deployer.MonitorMock
    |> expect(:start_service, fn _service -> {:ok, self()} end)
    |> expect(:stop_service, fn _name, _sname -> :ok end)
    |> expect(:state, fn _sname -> {:ok, %{}} end)
    |> expect(:restart, fn _sname -> :ok end)
    |> expect(:run_pre_commands, fn _sname, cmds, _new_or_current -> {:ok, cmds} end)

    assert {:ok, _pid} =
             Deployer.Monitor.start_service(%Service{
               name: name,
               sname: sname,
               language: "elixir",
               ports: ports
             })

    assert :ok = Deployer.Monitor.stop_service(name, sname)
    assert {:ok, %{}} = Deployer.Monitor.state(sname)
    assert :ok = Deployer.Monitor.restart(sname)
    assert {:ok, []} = Deployer.Monitor.run_pre_commands(sname, [], :new)
  end

  @tag :capture_log
  test "Do not change state when an invalid :check_running msg is received", %{
    elixir_name: name,
    elixir_sname: sname,
    ports: ports
  } do
    test_event_ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    FixtureFiles.create_bin_files(sname)

    Deployer.StatusMock
    |> stub(:current_version_map, fn ^sname ->
      %Catalog.Version{version: "1.0.0"}
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
             MonitorApp.start_service(%Service{
               name: name,
               sname: sname,
               language: "elixir",
               ports: ports,
               timeout_app_ready: 10
             })

    assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

    state = MonitorApp.state(sname)

    send(pid, {:check_running, :any, :any})

    :timer.sleep(100)

    assert state == MonitorApp.state(sname)

    assert :ok = MonitorApp.stop_service(name, sname)
  end
end
