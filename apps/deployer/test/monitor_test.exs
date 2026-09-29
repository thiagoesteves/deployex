defmodule Deployer.MonitorTest do
  use ExUnit.Case, async: false

  import Mox
  import Mock
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
               "Version: 1.0.0 set but no /tmp/var/lib/deployex/service/#{name}/#{sname}/current/bin/#{name}"
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
               "Version: 1.0.0 set but no /tmp/var/lib/deployex/service/#{name}/#{sname}/current/erlang-shipment"
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
               "Version: 1.0.0 set but no /tmp/var/lib/deployex/service/#{name}/#{sname}/current/bin/#{name}"
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
    test "Running application - elixir start command sets RELEASE_COOKIE",
         %{elixir_name: name, elixir_sname: sname, ports: ports} do
      test_event_ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> stub(:current_version_map, fn ^sname ->
        %Catalog.Version{version: "1.0.0"}
      end)

      Host.CommanderMock
      |> expect(:run_link, fn command, _options ->
        send(test_pid_process, {:start_command, command})
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
                 env: ["RELEASE_COOKIE=app-cookie"],
                 timeout_app_ready: 10
               })

      assert_receive {:start_command, command}, 1_000

      # The DeployEx cookie is a quoted default. The app's own env comes after it and wins.
      {default_at, _} = :binary.match(command, "export RELEASE_COOKIE='cookie'\n")
      {app_env_at, _} = :binary.match(command, "export RELEASE_COOKIE='app-cookie'")
      assert default_at < app_env_at

      assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

      assert :ok = MonitorApp.stop_service(name, sname)
    end

    for language <- ["elixir", "erlang", "gleam"] do
      @tag :capture_log
      test "Running application - #{language} start command quotes env values and the cookie",
           context do
        language = unquote(language)
        name = context[:"#{language}_name"]
        sname = context[:"#{language}_sname"]
        test_pid_process = self()
        FixtureFiles.create_bin_files(language, sname)

        Deployer.StatusMock
        |> stub(:current_version_map, fn ^sname ->
          %Catalog.Version{version: "1.0.0", sname: sname, name: name}
        end)

        Host.CommanderMock
        |> expect(:run_link, fn command, _options ->
          send(test_pid_process, {:start_command, command})
          {:ok, test_pid_process, 123_456}
        end)
        |> stub(:run, fn _command, _options -> {:ok, test_pid_process} end)
        |> stub(:stop, fn ^test_pid_process -> :ok end)

        assert {:ok, _pid} =
                 MonitorApp.start_service(%Service{
                   name: name,
                   sname: sname,
                   language: language,
                   ports: context.ports,
                   env: [
                     "TEST_SPACES=a b",
                     "TEST_SHELL=p$ss;(x)",
                     "TEST_QUOTE=it's",
                     "TEST_EQUALS=k=v"
                   ],
                   timeout_app_ready: 10
                 })

        assert_receive {:start_command, command}, 1_000

        # Run the generated export line in a real shell and read the values back
        [export_line] = command |> String.split("\n") |> Enum.filter(&(&1 =~ "TEST_SPACES"))

        {output, 0} =
          System.cmd("sh", [
            "-c",
            export_line <>
              ~s(; printf '%s|%s|%s|%s' "$TEST_SPACES" "$TEST_SHELL" "$TEST_QUOTE" "$TEST_EQUALS")
          ])

        assert output == "a b|p$ss;(x)|it's|k=v"

        if language == "gleam",
          do: assert(command =~ "-setcookie 'cookie'"),
          else: assert(command =~ "export RELEASE_COOKIE='cookie'\n")

        assert :ok = MonitorApp.stop_service(name, sname)
      end
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
    test "Pre-commands run one after the other and the result arrives as a message", context do
      test_pid = self()

      monitor =
        start_running_monitor(context, fn command ->
          send(test_pid, {:ran, command})
          exit_pre_command(:normal)
        end)

      assert {:ok, ref} =
               MonitorApp.start_pre_commands(context.elixir_sname, ["eval one", "eval two"], :new)

      # the worker learns the run started before the result
      assert_receive {:pre_commands_started, ^ref}, 1_000
      assert_receive {:pre_commands_result, ^ref, {:ok, ["eval one", "eval two"]}}, 1_000

      # its own process group, so a stop also ends the BEAM that `bin/app eval` starts
      assert_received {:pre_command_options, options}
      assert {:group, 0} in options and :kill_group in options

      assert_received {:ran, first}
      assert_received {:ran, second}
      assert first =~ "eval one" and second =~ "eval two"

      assert %{pre_commands_run: nil} = :sys.get_state(monitor)
      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A failing pre_command returns an error and keeps the application running", context do
      test_pid = self()

      monitor =
        start_running_monitor(context, fn command ->
          send(test_pid, {:ran, command})
          exit_pre_command({:exit_status, 256})
        end)

      %{current_pid: app_pid} = :sys.get_state(monitor)

      log =
        capture_log(fn ->
          assert {:ok, ref} =
                   MonitorApp.start_pre_commands(
                     context.elixir_sname,
                     ["eval failing_cmd", "eval never_runs"],
                     :new
                   )

          assert_receive {:pre_commands_result, ^ref, {:error, :pre_commands}}, 1_000
          send(self(), {:result_ref, ref})
        end)

      assert log =~ "Error running pre-command: eval failing_cmd"
      assert_received {:result_ref, ref}
      assert_received {:ran, _failing}
      refute_received {:ran, _never_runs}

      # a crash here would take the running application down with the monitor
      refute_received {:DOWN, ^ref, :process, _pid, _reason}
      assert %{current_pid: ^app_pid, pre_commands_run: nil} = :sys.get_state(monitor)
      assert %{status: :running} = MonitorApp.state(context.elixir_sname)

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A pre-command that cannot start returns an error", context do
      start_running_monitor(context, fn _command -> {:error, :enoent} end)

      assert {:ok, ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval x"], :new)
      assert_receive {:pre_commands_result, ^ref, {:error, :pre_commands}}, 1_000

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "The monitor answers while a pre-command runs, and a second request is busy", context do
      monitor = start_running_monitor(context, fn _command -> running_pre_command() end)

      assert {:ok, ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval slow"], :new)

      assert %{pre_commands_run: %{ref: ^ref}} = :sys.get_state(monitor, 100)
      assert %{status: :pre_commands} = MonitorApp.state(context.elixir_sname)

      assert {:ok, ref2} =
               MonitorApp.start_pre_commands(context.elixir_sname, ["eval other"], :new)

      assert_receive {:pre_commands_result, ^ref2, {:error, :busy}}, 1_000
      refute_received {:pre_commands_result, ^ref, _result}

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "Cancel stops the running pre-command and sends no result", context do
      test_pid = self()
      monitor = start_running_monitor(context, fn _command -> running_pre_command() end)

      Host.CommanderMock
      |> stub(:stop, fn pid ->
        send(test_pid, {:stopped, pid})
        :ok
      end)

      assert {:ok, ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval slow"], :new)
      %{pre_commands_run: %{os_pid: os_pid}} = :sys.get_state(monitor)

      assert :ok = MonitorApp.cancel_pre_commands(context.elixir_sname, ref)

      assert_receive {:stopped, ^os_pid}, 1_000
      assert %{pre_commands_run: nil} = :sys.get_state(monitor)
      refute_received {:pre_commands_result, ^ref, _result}

      # a cancel for a request that is gone changes nothing
      assert :ok = MonitorApp.cancel_pre_commands(context.elixir_sname, make_ref())
      assert %{pre_commands_run: nil} = :sys.get_state(monitor)

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "Stopping the monitor stops a running pre-command", context do
      test_pid = self()
      monitor = start_running_monitor(context, fn _command -> running_pre_command() end)

      Host.CommanderMock
      |> stub(:stop, fn pid ->
        send(test_pid, {:stopped, pid})
        :ok
      end)

      assert {:ok, _ref} =
               MonitorApp.start_pre_commands(context.elixir_sname, ["eval slow"], :new)

      %{pre_commands_run: %{os_pid: os_pid}} = :sys.get_state(monitor)

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
      assert_receive {:stopped, ^os_pid}, 1_000
    end

    @tag :capture_log
    test "A run is stopped when the process that asked for it exits", context do
      test_pid = self()
      monitor = start_running_monitor(context, fn _command -> running_pre_command() end)

      Host.CommanderMock
      |> stub(:stop, fn pid ->
        send(test_pid, {:stopped, pid})
        :ok
      end)

      requester =
        spawn(fn ->
          {:ok, _ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval slow"], :new)
          send(test_pid, :requested)
          receive do: (:exit -> :ok)
        end)

      assert_receive :requested, 1_000
      %{pre_commands_run: %{os_pid: os_pid}} = :sys.get_state(monitor)

      send(requester, :exit)

      assert_receive {:stopped, ^os_pid}, 1_000
      assert %{pre_commands_run: nil} = :sys.get_state(monitor)

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A restart asked for during a run waits until the run ends", context do
      test_pid = self()
      monitor = start_running_monitor(context, fn _command -> running_pre_command() end)

      Host.CommanderMock
      |> stub(:stop, fn pid ->
        send(test_pid, {:stopped, pid})
        :ok
      end)

      assert {:ok, ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval slow"], :new)
      %{pre_commands_run: %{os_pid: os_pid, exec_pid: exec_pid}} = :sys.get_state(monitor)

      assert :ok = MonitorApp.restart(context.elixir_sname)
      refute_receive {:stopped, _app_pid}, 100

      # the command ends, then the restart runs
      send(monitor, {:DOWN, os_pid, :process, exec_pid, :normal})

      # the pre_commands ran and the app is restarting, so the worker waits instead of upgrading
      assert_receive {:pre_commands_result, ^ref, {:error, :app_down}}, 1_000
      assert_receive {:stopped, ^test_pid}, 1_000
      assert %{force_restart_count: 1, pre_commands_run: nil} = :sys.get_state(monitor)

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "An application that exits during a run gets an app_down reply, not a result", context do
      monitor = start_running_monitor(context, fn _command -> running_pre_command() end)

      assert {:ok, ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval slow"], :new)
      %{current_pid: app_pid, pre_commands_run: run} = :sys.get_state(monitor)

      # the app crashes, then the command ends before the crash restart runs
      send(monitor, {:EXIT, app_pid, {:exit_status, 256}})
      send(monitor, {:DOWN, run.os_pid, :process, run.exec_pid, :normal})

      # the pre_commands ran, so the reply is not busy, which would make the worker run them again
      assert_receive {:pre_commands_result, ^ref, {:error, :app_down}}, 1_000

      # a request while the application is down ran nothing, so it is busy
      assert {:ok, ref2} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval x"], :new)
      assert_receive {:pre_commands_result, ^ref2, {:error, :busy}}, 1_000

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A request while a restart is starting the application is busy", context do
      start_running_monitor(context, fn _command -> exit_pre_command(:normal) end)

      assert :ok = MonitorApp.restart(context.elixir_sname)

      assert {:ok, ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval x"], :new)
      assert_receive {:pre_commands_result, ^ref, {:error, :busy}}, 500

      # before the restart starts the application again
      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A call from a worker of the previous version still runs its pre_commands", context do
      monitor = start_running_monitor(context, fn _command -> exit_pre_command(:normal) end)

      # the old worker installs after this reply, so the migration has to run first. It calls the
      # public function, which runs the newest code
      assert {:ok, ["eval x"]} =
               MonitorApp.run_pre_commands(context.elixir_sname, ["eval x"], :new)

      assert Process.alive?(monitor)

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A failing call from a worker of the previous version stops the monitor", context do
      test_pid = self()

      monitor =
        start_running_monitor(context, fn _command -> exit_pre_command({:exit_status, 256}) end)

      # the old call runs its commands with :sync, here the migration fails. The supervisor then
      # starts the monitor again, and it starts the application again
      Host.CommanderMock
      |> stub(:run, fn command, _options ->
        if command =~ "eval failing", do: {:error, [exit_status: 256]}, else: {:ok, test_pid}
      end)
      |> stub(:run_link, fn _command, _options ->
        send(test_pid, :started_again)
        {:ok, test_pid, 654_321}
      end)

      mref = Process.monitor(monitor)

      # the old worker installs whatever the reply says, so only a stop keeps the release out,
      # as the MatchError did before
      assert {:error, :pre_commands} =
               MonitorApp.run_pre_commands(context.elixir_sname, ["eval failing"], :new)

      assert_receive {:DOWN, ^mref, :process, ^monitor, :pre_commands_failed}, 1_000
      assert_receive :started_again, 2_000

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A restart does not count the stopped application as a crash", context do
      test_pid = self()
      monitor = start_running_monitor(context, fn _command -> exit_pre_command(:normal) end)
      %{current_pid: app_pid} = :sys.get_state(monitor)

      Host.CommanderMock
      |> stub(:run_link, fn _command, _options ->
        send(test_pid, :started_again)
        {:ok, test_pid, 654_321}
      end)

      assert :ok = MonitorApp.restart(context.elixir_sname)

      # the application that the restart stopped reports its exit
      send(monitor, {:EXIT, app_pid, {:exit_status, 143}})

      # one start from the restart, and no second one from a crash backoff
      assert_receive :started_again, 2_000
      refute_receive :started_again, 2_500

      assert %{crash_restart_count: 0, force_restart_count: 1} = :sys.get_state(monitor)

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A crash restart during a run waits until the run ends", context do
      test_pid = self()
      monitor = start_running_monitor(context, fn _command -> running_pre_command() end)

      Host.CommanderMock
      |> expect(:run_link, fn _command, _options ->
        send(test_pid, :started_again)
        {:ok, test_pid, 654_321}
      end)

      assert {:ok, ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval slow"], :new)
      %{pre_commands_run: %{os_pid: os_pid, exec_pid: exec_pid}} = :sys.get_state(monitor)

      send(monitor, {:run_service, context.elixir_sname})
      refute_receive :started_again, 200

      send(monitor, {:DOWN, os_pid, :process, exec_pid, :normal})

      # the pre_commands ran and the app is restarting, so the worker waits instead of upgrading
      assert_receive {:pre_commands_result, ^ref, {:error, :app_down}}, 1_000
      assert_receive :started_again, 1_000

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A deferred restart is skipped when the application is already down", context do
      test_pid = self()
      monitor = start_running_monitor(context, fn _command -> running_pre_command() end)

      Host.CommanderMock
      |> stub(:stop, fn pid ->
        send(test_pid, {:stopped, pid})
        :ok
      end)

      assert {:ok, ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval slow"], :new)
      %{pre_commands_run: %{os_pid: os_pid, exec_pid: exec_pid}} = :sys.get_state(monitor)

      assert :ok = MonitorApp.restart(context.elixir_sname)

      # the application exits before the run ends
      send(monitor, {:EXIT, test_pid, :crashed})
      send(monitor, {:DOWN, os_pid, :process, exec_pid, :normal})

      # the pre_commands ran and the app is down, so the worker waits instead of upgrading
      assert_receive {:pre_commands_result, ^ref, {:error, :app_down}}, 1_000
      refute_receive {:stopped, nil}, 200
      assert %{force_restart_count: 0, pre_commands_run: nil} = :sys.get_state(monitor)
      assert Process.alive?(monitor)

      # before the crash backoff starts the application again
      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    @tag :capture_log
    test "A monitor state without the run field from an older version accepts a request",
         context do
      test_pid = self()

      monitor =
        start_running_monitor(context, fn command ->
          send(test_pid, {:ran, command})
          exit_pre_command(:normal)
        end)

      # a relup that could not suspend the monitor leaves its old state in place
      :sys.replace_state(monitor, &Map.delete(&1, :pre_commands_run))

      assert {:ok, ref} = MonitorApp.start_pre_commands(context.elixir_sname, ["eval one"], :new)
      assert_receive {:pre_commands_result, ^ref, {:ok, ["eval one"]}}, 1_000

      assert :ok = MonitorApp.stop_service(context.elixir_name, context.elixir_sname)
    end

    test "A pre_command request for a monitor that is not running returns an error" do
      sname = "myelixir-notrunning"
      _atom = String.to_atom(sname)

      assert {:error, :not_running} =
               MonitorApp.start_pre_commands(sname, ["eval Migrate.run"], :new)
    end

    test "code_change adds the pre-commands run field to a state from an older version" do
      old_state = Map.delete(%Deployer.Monitor{sname: "myelixir-abc"}, :pre_commands_run)

      assert {:ok, %Deployer.Monitor{sname: "myelixir-abc", pre_commands_run: nil}} =
               MonitorApp.code_change("0.10.0", old_state, [])
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
    test "consecutive_crash_count resets to 0 after application reports running", %{
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
      |> stub(:run_link, fn _command, _options ->
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

      assert %{status: :running, crash_restart_count: 0, consecutive_crash_count: 0} =
               MonitorApp.state(sname)

      # Crash the application
      send(pid, {:EXIT, test_pid_process, :forcing_restart})

      # Wait for the backoff (2 * 1 * 1000 = 2000ms) plus margin for check_running
      :timer.sleep(2_500)

      # After the restart and check_running fires, the backoff counter resets while
      # the lifetime crash_restart_count is preserved
      assert %{status: :running, crash_restart_count: 1, consecutive_crash_count: 0} =
               MonitorApp.state(sname)

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
      # the two pre_commands and the restart's cleanup. The stop right after the restart finds
      # the application already stopped, so it runs no second cleanup
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

    @tag :capture_log
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
    |> expect(:start_pre_commands, fn _sname, _cmds, _new_or_current -> {:ok, make_ref()} end)
    |> expect(:cancel_pre_commands, fn _sname, _ref -> :ok end)

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
    assert {:ok, ["eval x"]} = Deployer.Monitor.run_pre_commands(sname, ["eval x"], :new)
    assert {:ok, ref} = Deployer.Monitor.start_pre_commands(sname, [], :new)
    assert is_reference(ref)
    assert :ok = Deployer.Monitor.cancel_pre_commands(sname, ref)
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

  test "list/1" do
    Deployer.MonitorMock
    |> expect(:list, fn _options -> [] end)

    assert [] == Deployer.Monitor.list([])
  end

  test "subscribe_new_deploy/0" do
    Deployer.MonitorMock
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    assert :ok == Deployer.Monitor.subscribe_new_deploy()
  end

  test "init_all_monitor_supervisors/0" do
    with_mock DynamicSupervisor, [:passthrough],
      start_child: fn _module, _spec -> {:ok, self()} end do
      assert :ok == Deployer.Monitor.init_all_monitor_supervisors()
    end
  end

  # Starts a monitor with a running application. `pre_command` answers each pre-command the
  # monitor starts, and runs in the monitor process, as erlexec does
  defp start_running_monitor(%{elixir_name: name, elixir_sname: sname, ports: ports}, pre_command) do
    test_pid = self()
    ref = make_ref()
    FixtureFiles.create_bin_files(sname)

    Deployer.StatusMock
    |> stub(:current_version_map, fn ^sname -> %Catalog.Version{version: "1.0.0"} end)

    Host.CommanderMock
    |> expect(:run_link, fn _command, _options ->
      Process.send_after(test_pid, {:handle_ref_event, ref}, 100)
      {:ok, test_pid, 123_456}
    end)
    |> stub(:run, fn command, options ->
      if :monitor in options do
        send(test_pid, {:pre_command_options, options})
        pre_command.(command)
      else
        {:ok, test_pid}
      end
    end)
    |> stub(:stop, fn _pid -> :ok end)

    assert {:ok, monitor} =
             MonitorApp.start_service(%Service{
               name: name,
               sname: sname,
               language: "elixir",
               ports: ports,
               timeout_app_ready: 10
             })

    assert_receive {:handle_ref_event, ^ref}, 1_000
    monitor
  end

  # erlexec reports the end of a monitored command with a DOWN message keyed by the OS pid
  defp exit_pre_command(reason) do
    {exec_pid, os_pid} = {spawn(fn -> :ok end), System.unique_integer([:positive])}
    send(self(), {:DOWN, os_pid, :process, exec_pid, reason})
    {:ok, exec_pid, os_pid}
  end

  # Linked to the monitor that starts it, so it ends with the monitor
  defp running_pre_command do
    exec_pid = spawn_link(fn -> Process.sleep(:infinity) end)
    {:ok, exec_pid, System.unique_integer([:positive])}
  end
end
