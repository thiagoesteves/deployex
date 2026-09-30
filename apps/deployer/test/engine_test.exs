defmodule Deployer.EngineTest do
  use ExUnit.Case, async: false

  import Mox
  import Mock
  import ExUnit.CaptureLog

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployer.Engine
  alias Deployer.Fixture.Files, as: FixtureFiles
  alias Foundation.Catalog
  alias Foundation.Fixture.Catalog, as: FixtureCatalog

  setup do
    # Every worker subscribes and then reads the list on start up, the tests that care about
    # the ghosted list override these with their own expectations
    stub(Deployer.StatusMock, :subscribe_ghosted_versions, fn name ->
      Phoenix.PubSub.subscribe(Deployer.PubSub, "deployex::ghosted_versions::#{name}")
    end)

    stub(Deployer.StatusMock, :ghosted_version_list, fn _name -> [] end)

    # A worker reads the monitor state of each installed sname on start up. No monitor runs
    # unless a test says so
    stub(Deployer.MonitorMock, :state, fn _sname -> %Deployer.Monitor{} end)

    FixtureCatalog.cleanup()
  end

  describe "Initialization tests" do
    @tag :capture_log
    test "init/1" do
      name = "myelixir"
      language = "elixir"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 5_000,
                   name: name,
                   language: language
                 })

        assert {:error, {:already_started, _pid}} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 5_000,
                   name: name,
                   language: language
                 })
      end
    end

    @tag :capture_log
    test "Initialization with version not configured" do
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> expect(:current_version, 1, fn _sname -> "1.0.0" end)
      |> expect(:update, 0, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 0, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:stop_service, 0, fn _name, _sname -> :ok end)
      |> expect(:start_service, 0, fn _service ->
        {:ok, self()}
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        nil
      end)
      |> expect(:download_release, 0, fn _app_name, _version, _download_path -> :ok end)

      assert capture_log(fn ->
               with_mock System, [:passthrough],
                 cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
                 assert {:ok, _pid} =
                          Engine.Worker.start_link(%Engine.Worker{
                            deploy_rollback_timeout_ms: 1_000,
                            deploy_schedule_interval_ms: 100,
                            name: name,
                            language: language
                          })

                 assert_receive {:handle_ref_event, ^ref}, 1_000
               end
             end) =~ "No versions set yet for myelixir"
    end

    @tag :capture_log
    test "Initialization with version configured" do
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()
      sname = Catalog.create_sname("myelixir")
      FixtureFiles.create_bin_files(sname)
      version = "1.2.3"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> expect(:current_version, 2, fn _sname -> version end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: version}]
      end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn %{sname: ^sname} ->
        send(pid, {:handle_ref_event, ref})
        {:ok, self()}
      end)

      Deployer.ReleaseMock
      |> expect(:download_version_map, 0, fn _app_name -> nil end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end
  end

  describe "Engine worker restart resilience" do
    @tag :capture_log
    test "Initialization tolerates an already running monitor service" do
      # Monitors live in a separate supervision tree, so when the engine
      # worker is restarted by its supervisor the monitor for the installed
      # application may still be running
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()
      sname = Catalog.create_sname("myelixir")
      FixtureFiles.create_bin_files(sname)
      version = "1.2.3"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> stub(:current_version, fn _sname -> version end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: version}]
      end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn %{sname: ^sname} ->
        send(pid, {:handle_ref_event, ref})
        {:error, {:already_started, self()}}
      end)
      |> stub(:state, fn ^sname ->
        %Deployer.Monitor{sname: sname, current_pid: self(), status: :running}
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version, hash: "local", pre_commands: []}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker_pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000

        # Let the engine run a few schedule cycles after initialization
        :timer.sleep(300)

        assert Process.alive?(worker_pid)

        state = :sys.get_state(String.to_atom(name))
        assert %Deployer.Engine.Deployment{sname: ^sname, state: :active} = state.deployments[1]
      end
    end

    @tag :capture_log
    test "Application running notification before the rollback timer is armed" do
      # A monitor that survived an engine worker restart can report the
      # application running before the engine arms any rollback timer
      name = "myelixir"
      language = "elixir"

      sname = Catalog.create_sname("myelixir")
      FixtureFiles.create_bin_files(sname)
      version = "1.2.3"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> stub(:current_version, fn _sname -> version end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: version}]
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker_pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 60_000,
                   name: name,
                   language: language
                 })

        # No schedule cycle has run yet, so no rollback timer is armed
        Engine.notify_application_running(sname)

        state = :sys.get_state(String.to_atom(name))

        assert Process.alive?(worker_pid)
        assert state.current == 1
      end
    end

    @tag :capture_log
    test "A restart does not stop an app its monitor already runs after the rollback timeout" do
      name = "myelixir"
      test_pid = self()
      sname = Catalog.create_sname(name)
      FixtureFiles.create_bin_files(sname)
      version = "1.2.3"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> stub(:current_version, fn _sname -> version end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: version}]
      end)
      |> stub(:add_ghosted_version, fn version_map ->
        send(test_pid, {:ghosted, version_map})
        {:ok, [version_map]}
      end)
      |> stub(:current_version_map, fn _sname ->
        %{version: version, hash: "local", pre_commands: []}
      end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn %{sname: ^sname} -> {:error, {:already_started, self()}} end)
      |> stub(:state, fn ^sname ->
        %Deployer.Monitor{sname: sname, current_pid: self(), status: :running}
      end)
      |> stub(:stop_service, fn _name, sname ->
        send(test_pid, {:stopped, sname})
        :ok
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version, hash: "local", pre_commands: []}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker_pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 100,
                   deploy_schedule_interval_ms: 50,
                   name: name,
                   language: "elixir"
                 })

        # Several rollback timeouts pass, the monitor never reports the app running again
        refute_receive {:stopped, _sname}, 500
        refute_received {:ghosted, _version_map}

        assert Process.alive?(worker_pid)

        assert %{current: 1, deployments: %{1 => deployment}} = :sys.get_state(worker_pid)
        assert %Engine.Deployment{sname: ^sname, state: :active, timer_ref: nil} = deployment
      end
    end

    @tag :capture_log
    test "A restart with every replica already running initializes each one without a window" do
      name = "myelixir"
      test_pid = self()
      sname_1 = Catalog.create_sname(name)
      sname_2 = Catalog.create_sname(name)
      FixtureFiles.create_bin_files(sname_1)
      FixtureFiles.create_bin_files(sname_2)
      version = "1.2.3"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname_1, sname_2] end)
      |> stub(:current_version, fn _sname -> version end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: version}]
      end)

      Deployer.MonitorMock
      |> stub(:start_service, fn %{sname: sname} ->
        send(test_pid, {:start_service, sname})
        {:error, {:already_started, self()}}
      end)
      |> stub(:state, fn sname ->
        %Deployer.Monitor{sname: sname, current_pid: self(), status: :running}
      end)
      |> expect(:stop_service, 0, fn _name, _sname -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version, hash: "local", pre_commands: []}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker_pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   replicas: 2,
                   deploy_rollback_timeout_ms: 100,
                   deploy_schedule_interval_ms: 50,
                   name: name,
                   language: "elixir"
                 })

        assert_receive {:start_service, ^sname_1}, 1_000
        assert_receive {:start_service, ^sname_2}, 1_000

        # Past the rollback timeout of both instances
        Process.sleep(300)

        assert %{current: 1, deployments: deployments} = :sys.get_state(worker_pid)

        assert %Engine.Deployment{sname: ^sname_1, state: :active, timer_ref: nil} =
                 deployments[1]

        assert %Engine.Deployment{sname: ^sname_2, state: :active, timer_ref: nil} =
                 deployments[2]
      end
    end

    @tag :capture_log
    test "A restart keeps the ports a running app holds out of the next full deployment" do
      name = "myelixir"
      test_pid = self()
      sname = Catalog.create_sname(name)
      FixtureFiles.create_bin_files(sname)

      # The first full deployment moved instance 1 to the spare set, base + replicas
      running_ports = [%{key: "PORT", base: 4001}]

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: "1.0.0"}]
      end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> stub(:start_service, fn
        %{sname: ^sname} ->
          {:error, {:already_started, self()}}

        %{sname: new_sname, ports: ports} ->
          send(test_pid, {:full_deployment, new_sname, ports})
          {:ok, self()}
      end)
      |> stub(:state, fn
        ^sname ->
          %Deployer.Monitor{
            sname: sname,
            current_pid: self(),
            status: :running,
            ports: running_ports
          }

        _sname ->
          %Deployer.Monitor{}
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0,
          do: %{version: "2.0.0", hash: "local", pre_commands: []},
          else: %{version: "1.0.0", hash: "local", pre_commands: []}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> stub(:check, fn check -> {:ok, %{check | deploy: :full_deployment}} end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   replica_ports: [%{key: "PORT", base: 4000}],
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 50,
                   name: name,
                   language: "elixir"
                 })

        assert_receive {:full_deployment, _new_sname, [%{key: "PORT", base: 4000}]}, 1_000
      end
    end

    test "A restart gives the other instances and the spare set only the ports nobody holds" do
      name = "myelixir"
      sname = Catalog.create_sname(name)
      FixtureFiles.create_bin_files(sname)

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: "1.0.0"}]
      end)

      Deployer.MonitorMock
      |> stub(:state, fn ^sname ->
        %Deployer.Monitor{sname: sname, ports: [%{key: "PORT", base: 4001}]}
      end)

      assert {:ok, worker_pid} =
               Engine.Worker.start_link(%Engine.Worker{
                 replicas: 2,
                 replica_ports: [%{key: "PORT", base: 4000}],
                 deploy_rollback_timeout_ms: 60_000,
                 # no scheduled check lands during the test
                 deploy_schedule_interval_ms: 60_000,
                 name: name,
                 language: "elixir"
               })

      assert %{deployments: deployments, available_ports: [%{key: "PORT", base: 4002}]} =
               :sys.get_state(worker_pid)

      assert %Engine.Deployment{sname: ^sname, ports: [%{key: "PORT", base: 4001}]} =
               deployments[1]

      assert %Engine.Deployment{sname: nil, ports: [%{key: "PORT", base: 4000}]} = deployments[2]
    end

    @tag :capture_log
    test "A restart while the monitor still starts the app keeps the rollback window" do
      name = "myelixir"
      sname = Catalog.create_sname(name)
      FixtureFiles.create_bin_files(sname)
      version = "1.2.3"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> stub(:current_version, fn _sname -> version end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: version}]
      end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn %{sname: ^sname} -> {:error, {:already_started, self()}} end)
      |> stub(:state, fn ^sname ->
        %Deployer.Monitor{sname: sname, current_pid: self(), status: :starting}
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version, hash: "local", pre_commands: []}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker_pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 50,
                   name: name,
                   language: "elixir"
                 })

        Process.sleep(200)

        # The monitor reports the app running once it starts, which closes the window
        assert %{deployments: %{1 => deployment}} = :sys.get_state(worker_pid)
        assert %Engine.Deployment{state: :active, deploying?: true} = deployment
        assert is_reference(deployment.timer_ref)
      end
    end
  end

  describe "Checking deployment" do
    @tag :capture_log
    test "Check for new version - full deployment - no pre-commands" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 1 do
          to_version
        else
          from_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _service ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> expect(:download_version_map, 2, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end

    @tag :capture_log
    test "Check for new version - ignore ghosted version" do
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()

      ghosted_version = "2.0.0"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> expect(:update, 1, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 1, fn _sname, _release, _attrs -> :ok end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:ghosted_version_list, fn ^name -> [%{version: ghosted_version}] end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _service ->
        {:ok, self()}
      end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> expect(:download_release, 1, fn _app_name, "1.0.0", _download_path ->
        :ok
      end)
      |> stub(:download_version_map, fn _app_name ->
        # Leave check deployment running for a few cycles
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          Process.send_after(pid, {:handle_ref_event, ref}, 100)
          %{version: ghosted_version, hash: "local", pre_commands: []}
        else
          %{version: "1.0.0", hash: "local", pre_commands: []}
        end
      end)

      Deployer.HotUpgradeMock
      |> expect(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end

    @tag :capture_log
    test "Check for new version - hotupgrade - pre-commands" do
      name = "myelixir"
      language = "elixir"

      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # 0 -> check_deployment
        # 1 -> hotupgrade before upgrade
        # 2 -> after hotupgrade
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          to_version
        else
          from_version
        end
      end)
      |> expect(:update, 1, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs ->
        # 0 -> 1.0.0
        # 1 -> 2.0.0
        called = Process.get("set_current_version_map", 0)
        Process.put("set_current_version_map", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        :ok
      end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _service ->
        {:ok, self()}
      end)
      |> expect(:stop_service, 1, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
        reply_pre_commands({:ok, ["eval Migrate.run"]})
      end)

      Deployer.ReleaseMock
      |> expect(:download_version_map, 3, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        # Third time: the version check before the upgrade installs
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: ["eval Migrate.run"]}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :hot_upgrade}}
      end)
      |> expect(:execute, 1, fn %Deployer.HotUpgrade.Execute{
                                  from_version: ^from_version,
                                  to_version: ^to_version
                                } ->
        :ok
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end

    test "Failure on executing the hotupgrade - pre-commands" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # keep the version unchanged, triggering full deployment
        from_version
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _service ->
        # First time: initialization
        # Second time: new deployment, after hotupgrade fails
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
        reply_pre_commands({:ok, ["eval Migrate.run"]})
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: to_version, hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, ^to_version, _download_path ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :hot_upgrade}}
      end)
      |> expect(:execute, 1, fn %Deployer.HotUpgrade.Execute{
                                  from_version: ^from_version,
                                  to_version: ^to_version
                                } ->
        {:error, "any"}
      end)

      assert capture_log(fn ->
               with_mock System, [:passthrough],
                 cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
                 assert {:ok, _pid} =
                          Engine.Worker.start_link(%Engine.Worker{
                            deploy_rollback_timeout_ms: 1_000,
                            deploy_schedule_interval_ms: 200,
                            name: name,
                            language: language
                          })

                 assert_receive {:handle_ref_event, ^ref}, 1_000
               end
             end) =~ "Hot Upgrade failed, running for full deployment"
    end

    test "Failure on executing the hotupgrade - not installed, ghost the version" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> from_version end)
      |> expect(:update, 1, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 1, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 1, fn version_map ->
        # the version that failed has to be the ghosted one, the running version is fine
        assert version_map.version == to_version
        assert version_map.name == name

        send(pid, {:handle_ref_event, ref})
        {:ok, [version_map]}
      end)

      Deployer.MonitorMock
      # only the initial deployment, a hot upgrade that never installed anything must not
      # start a new instance
      |> expect(:start_service, 1, fn _service -> {:ok, self()} end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: to_version, hash: "local", pre_commands: []}
      end)
      |> stub(:download_release, fn _app_name, ^to_version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{} = check ->
        {:ok, %{check | deploy: :hot_upgrade}}
      end)
      # the release claimed it could hot upgrade and then failed before install_release,
      # so the node is still running from_version and there is nothing to recover from
      |> expect(:execute, 1, fn %Deployer.HotUpgrade.Execute{to_version: ^to_version} ->
        {:error, {:not_installed, :make_relup}}
      end)

      log =
        capture_log(fn ->
          with_mock System, [:passthrough],
            cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
            assert {:ok, _pid} =
                     Engine.Worker.start_link(%Engine.Worker{
                       deploy_rollback_timeout_ms: 1_000,
                       deploy_schedule_interval_ms: 100,
                       name: name,
                       language: language
                     })

            assert_receive {:handle_ref_event, ^ref}, 1_000

            # the version is ghosted in the worker state as well, so the next scheduled
            # deployment skips it instead of trying the same broken release again
            refute_receive {:handle_ref_event, ^ref}, 300
          end
        end)

      assert log =~ "Hot upgrade failed before the release was installed"
      assert log =~ "ghosting version #{to_version}"
      refute log =~ "running for full deployment"
    end

    test "A hot upgrade whose node cannot be reached deploys fully, no ghost" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      # the start-up deployment, then the full deployment of the release
      |> expect(:start_service, 2, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: []}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      # a monitored app that is down, for example in a crash loop, cannot be connected to
      |> expect(:execute, 1, fn _execute -> {:error, {:unreachable, :not_connecting}} end)

      log =
        capture_log(fn ->
          with_mock System, [:passthrough],
            cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
            assert {:ok, _pid} =
                     Engine.Worker.start_link(%Engine.Worker{
                       deploy_rollback_timeout_ms: 60_000,
                       deploy_schedule_interval_ms: 50,
                       name: "myelixir",
                       language: "elixir"
                     })

            assert_receive {:started, sname}, 1_000
            Engine.notify_application_running(sname)

            assert_receive {:started, new_sname}, 2_000
            assert new_sname != sname
          end
        end)

      assert log =~ "Hot Upgrade failed, running for full deployment"
      refute log =~ "ghosting version"
    end

    for {mode, log_line} <- [
          failed: "Hot upgrade failed before the release was installed",
          no_reply: "did not finish within 1000 ms, stopping them"
        ] do
      @mode mode
      @log_line log_line
      test "Failure on the hotupgrade pre-commands (#{mode}) - do not upgrade, ghost the version" do
        name = "myelixir"
        language = "elixir"
        from_version = "1.0.0"
        to_version = "2.0.0"
        ref = make_ref()
        pid = self()

        Deployer.StatusMock
        |> expect(:list_installed_apps, fn _name -> [] end)
        |> stub(:current_version, fn _sname -> from_version end)
        |> expect(:update, 1, fn _sname -> :ok end)
        |> expect(:set_current_version_map, 1, fn _sname, _release, _attrs -> :ok end)
        |> expect(:add_ghosted_version, 1, fn version_map ->
          assert version_map.version == to_version

          send(pid, {:handle_ref_event, ref})
          {:ok, [version_map]}
        end)

        Deployer.MonitorMock
        # only the initial deployment, the running instance keeps serving from_version
        |> expect(:start_service, 1, fn service ->
          send(pid, {:started, service.sname})
          {:ok, self()}
        end)
        # only the empty start-up placeholder is terminated, never the running instance
        |> expect(:stop_service, 1, fn _name, nil -> :ok end)
        |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
          pre_commands_reply(@mode)
        end)
        # only a timeout stops the command, the other outcomes have already ended it
        |> expect(:cancel_pre_commands, if(@mode == :no_reply, do: 1, else: 0), fn _sname, _ref ->
          :ok
        end)

        Deployer.ReleaseMock
        |> stub(:download_version_map, fn _app_name ->
          %{version: to_version, hash: "local", pre_commands: ["eval Migrate.run"]}
        end)
        |> stub(:download_release, fn _app_name, ^to_version, _download_path -> :ok end)

        Deployer.HotUpgradeMock
        |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
        |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{} = check ->
          {:ok, %{check | deploy: :hot_upgrade}}
        end)
        # the migration did not run, so the release must not be installed
        |> expect(:execute, 0, fn _execute -> :ok end)

        log =
          capture_log(fn ->
            with_mock System, [:passthrough],
              cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
              assert {:ok, _pid} =
                       Engine.Worker.start_link(%Engine.Worker{
                         deploy_rollback_timeout_ms: 1_000,
                         deploy_schedule_interval_ms: 100,
                         name: name,
                         language: language
                       })

              # the initial instance is up, so its own rollback timer does not fire
              assert_receive {:started, sname}, 1_000
              Engine.notify_application_running(sname)

              assert_receive {:handle_ref_event, ^ref}, 2_000

              refute_receive {:handle_ref_event, ^ref}, 300
            end
          end)

        assert log =~ @log_line
        assert log =~ "Hot upgrade failed before the release was installed"
        assert log =~ "reason: :pre_commands"
        assert log =~ "ghosting version #{to_version}"
        refute log =~ "running for full deployment"
      end
    end

    test "The worker stays responsive and starts no second request while pre-commands run" do
      name = "myelixir"
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> expect(:update, 1, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 1, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _service -> {:ok, self()} end)
      # a migration that has not finished yet, the reply never comes in this test
      |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
        send(pid, :pre_commands_requested)
        {:ok, make_ref()}
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{} = check ->
        {:ok, %{check | deploy: :hot_upgrade}}
      end)
      |> expect(:execute, 0, fn _execute -> :ok end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 50,
                   name: name,
                   language: "elixir"
                 })

        assert_receive :pre_commands_requested, 1_000

        # several schedule ticks pass, the worker answers sys messages at once
        Process.sleep(300)

        assert %Engine.Worker{pending_pre_commands: %{release: %{version: "2.0.0"}}} =
                 :sys.get_state(worker, 100)
      end
    end

    test "A busy monitor is asked again without a new download, the release is not ghosted" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      # the mocks run in the worker, so its dictionary tracks whether the upgrade ran
      |> stub(:current_version, fn _sname ->
        if Process.get(:upgraded), do: "2.0.0", else: "1.0.0"
      end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      # only the empty start-up placeholder is terminated, never the running instance
      |> expect(:stop_service, 1, fn _name, nil -> :ok end)
      |> expect(:start_pre_commands, 2, fn _sname, ["eval Migrate.run"], :new ->
        called = Process.get(:requests, 0)
        Process.put(:requests, called + 1)

        if called == 0,
          do: reply_pre_commands({:error, :busy}),
          else: reply_pre_commands({:ok, ["eval Migrate.run"]})
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      # the retry asks the monitor again, without a new download and check
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{} = check ->
        {:ok, %{check | deploy: :hot_upgrade}}
      end)
      |> expect(:execute, 1, fn _execute ->
        Process.put(:upgraded, true)
        send(pid, :upgraded)
        :ok
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _worker} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 50,
                   name: "myelixir",
                   language: "elixir"
                 })

        assert_receive {:started, sname}, 1_000
        Engine.notify_application_running(sname)

        assert_receive :upgraded, 2_000
      end
    end

    for gone <- [:not_running, :noproc, :crashed] do
      @gone gone
      test "A monitor that is gone (#{gone}) falls back to a full deployment, no ghost" do
        pid = self()

        Deployer.StatusMock
        |> expect(:list_installed_apps, fn _name -> [] end)
        |> stub(:current_version, fn _sname -> "1.0.0" end)
        |> stub(:update, fn _sname -> :ok end)
        |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
        |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

        Deployer.MonitorMock
        # the start-up deployment, then the fallback full deployment
        |> expect(:start_service, 2, fn service ->
          send(pid, {:started, service.sname})
          {:ok, self()}
        end)
        |> stub(:stop_service, fn _name, _sname -> :ok end)
        |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
          first_pre_commands_reply(@gone)
        end)

        Deployer.ReleaseMock
        |> stub(:download_version_map, fn _app_name ->
          %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
        end)
        |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

        Deployer.HotUpgradeMock
        |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
        |> expect(:check, 1, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
        |> expect(:execute, 0, fn _execute -> :ok end)

        with_mock System, [:passthrough],
          cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
          assert {:ok, _worker} =
                   Engine.Worker.start_link(%Engine.Worker{
                     deploy_rollback_timeout_ms: 60_000,
                     deploy_schedule_interval_ms: 50,
                     name: "myelixir",
                     language: "elixir"
                   })

          assert_receive {:started, sname}, 1_000
          Engine.notify_application_running(sname)

          assert_receive {:started, new_sname}, 2_000
          assert new_sname != sname
        end
      end
    end

    for change <- [:restart, :replicas, :replica_ports] do
      @change change
      test "A #{change} while pre-commands run ends the request without a ghost or an upgrade" do
        pid = self()
        name = "myelixir"

        Deployer.StatusMock
        |> expect(:list_installed_apps, fn _name -> [] end)
        |> stub(:current_version, fn _sname -> "1.0.0" end)
        |> stub(:update, fn _sname -> :ok end)
        |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
        |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

        Deployer.MonitorMock
        |> stub(:start_service, fn service ->
          send(pid, {:started, service.sname})
          {:ok, self()}
        end)
        |> stub(:stop_service, fn _name, _sname -> :ok end)
        |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
          ref = make_ref()
          send(pid, {:requested, ref})
          {:ok, ref}
        end)
        # each change ends the request and stops its migration
        |> expect(:cancel_pre_commands, 1, fn _sname, _ref ->
          send(pid, :cancelled)
          :ok
        end)

        Deployer.ReleaseMock
        |> stub(:download_version_map, fn _app_name ->
          %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
        end)
        |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

        Deployer.HotUpgradeMock
        |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
        # only the first check offers a hot upgrade, later ones deploy fully
        |> stub(:check, fn %Deployer.HotUpgrade.Check{} = check ->
          called = Process.get(:checks, 0)
          Process.put(:checks, called + 1)
          deploy = if called == 0, do: :hot_upgrade, else: :full_deployment
          {:ok, %{check | deploy: deploy}}
        end)
        |> expect(:execute, 0, fn _execute -> :ok end)

        with_mock System, [:passthrough],
          cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
          assert {:ok, worker} =
                   Engine.Worker.start_link(%Engine.Worker{
                     deploy_rollback_timeout_ms: 60_000,
                     deploy_schedule_interval_ms: 50,
                     name: name,
                     language: "elixir"
                   })

          assert_receive {:started, sname}, 1_000
          Engine.notify_application_running(sname)
          assert_receive {:requested, ref}, 1_000

          case @change do
            :restart ->
              Engine.Worker.restart_deployments(name)
              assert_receive :cancelled, 1_000

            :replicas ->
              Engine.Worker.updated_state_values(name, %{replicas: 2})
              assert_receive :cancelled, 1_000

            :replica_ports ->
              Engine.Worker.updated_state_values(name, %{
                replica_ports: [%{key: "PORT", base: 5000}]
              })

              assert_receive :cancelled, 1_000
          end

          # a reply that arrives after the change is ignored
          send(worker, {:pre_commands_result, ref, {:ok, ["eval Migrate.run"]}})

          assert %Engine.Worker{pending_pre_commands: nil} = :sys.get_state(worker)
          assert Process.alive?(worker)
        end
      end
    end

    test "With two replicas, a monitored app that comes back after app_down takes the upgrade" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn sname ->
        if sname in Process.get(:upgraded, []), do: "2.0.0", else: "1.0.0"
      end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      |> stub(:start_service, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> stub(:start_pre_commands, fn sname, pre_commands, :new ->
        send(pid, {:requested, sname, pre_commands})
        ref = make_ref()
        send(self(), {:pre_commands_started, ref})

        # the first run is answered by the test, the empty-list retry at once
        if pre_commands == [],
          do: send(self(), {:pre_commands_result, ref, {:ok, []}}),
          else: send(pid, {:run_ref, sname, ref})

        {:ok, ref}
      end)
      |> expect(:cancel_pre_commands, 0, fn _sname, _ref -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> stub(:check, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      |> stub(:execute, fn execute ->
        Process.put(:upgraded, [execute.sname | Process.get(:upgraded, [])])
        send(pid, {:upgraded, execute.sname})
        :ok
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 50,
                   name: "myelixir",
                   language: "elixir"
                 })

        assert_receive {:started, sname}, 1_000

        # a second replica already runs 1.0.0
        :sys.replace_state(worker, fn state ->
          %{
            state
            | replicas: 2,
              deployments:
                Map.put(state.deployments, 2, %Engine.Deployment{
                  state: :active,
                  sname: "myelixir-other"
                })
          }
        end)

        Engine.notify_application_running(sname)
        assert_receive {:run_ref, "myelixir-other", ref}, 1_000
        assert_received {:requested, "myelixir-other", ["eval Migrate.run"]}

        # the monitored app went down during the run, then comes back before the retry
        send(worker, {:pre_commands_result, ref, {:error, :app_down}})
        Engine.notify_application_running("myelixir-other")

        assert_receive {:requested, "myelixir-other", []}, 1_000
        assert_receive {:upgraded, "myelixir-other"}, 1_000
        refute_received {:requested, "myelixir-other", ["eval Migrate.run"]}
      end
    end

    test "Removing replicas keeps a pending request on a remaining instance current" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 1, fn version_map ->
        send(pid, :ghosted)
        {:ok, [version_map]}
      end)

      Deployer.MonitorMock
      |> stub(:start_service, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 1, fn sname, ["eval Migrate.run"], :new ->
        ref = make_ref()
        send(self(), {:pre_commands_started, ref})
        send(pid, {:run_ref, sname, ref})
        {:ok, ref}
      end)
      |> expect(:cancel_pre_commands, 0, fn _sname, _ref -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> stub(:check, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      |> expect(:execute, 0, fn _execute -> :ok end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 50,
                   name: "myelixir",
                   language: "elixir"
                 })

        assert_receive {:started, sname}, 1_000

        :sys.replace_state(worker, fn state ->
          %{
            state
            | replicas: 3,
              deployments:
                state.deployments
                |> Map.put(2, %Engine.Deployment{state: :active, sname: "myelixir-two"})
                |> Map.put(3, %Engine.Deployment{state: :active, sname: "myelixir-three"})
          }
        end)

        Engine.notify_application_running(sname)
        assert_receive {:run_ref, "myelixir-two", ref}, 1_000

        # instance 2 stays, so its request stays and its outcome still counts
        Engine.Worker.updated_state_values("myelixir", %{replicas: 2})

        assert %Engine.Worker{current: 2, pending_pre_commands: %{instance: 2}} =
                 :sys.get_state(worker)

        send(worker, {:pre_commands_result, ref, {:error, :pre_commands}})
        assert_receive :ghosted, 1_000
      end
    end

    test "Removing the replica that has a pending request stops its command" do
      pid = self()
      name = "myelixir"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      |> stub(:start_service, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
        send(pid, :requested)
        {:ok, make_ref()}
      end)
      |> expect(:cancel_pre_commands, 1, fn _sname, _ref ->
        send(pid, :cancelled)
        :ok
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> stub(:check, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      |> expect(:execute, 0, fn _execute -> :ok end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 50,
                   name: name,
                   language: "elixir"
                 })

        assert_receive {:started, sname}, 1_000
        Engine.notify_application_running(sname)
        assert_receive :requested, 1_000

        # the pending request belongs to instance 2 of 2
        :sys.replace_state(worker, fn state ->
          %{
            state
            | replicas: 2,
              current: 2,
              deployments: Map.put(state.deployments, 2, state.deployments[1]),
              pending_pre_commands: %{state.pending_pre_commands | instance: 2}
          }
        end)

        Engine.Worker.updated_state_values(name, %{replicas: 1})

        assert_receive :cancelled, 1_000
        assert %Engine.Worker{pending_pre_commands: nil, replicas: 1} = :sys.get_state(worker)
      end
    end

    test "A timeout for an instance that is no longer current stops its command" do
      pid = self()
      name = "myelixir"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      # every instance reports running, so no deployment's own rollback timer fires
      |> stub(:start_service, fn service ->
        Engine.notify_application_running(service.sname)
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
        send(pid, :requested)
        {:ok, make_ref()}
      end)
      |> expect(:cancel_pre_commands, 1, fn _sname, _ref ->
        send(pid, :cancelled)
        :ok
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      # only the first check offers a hot upgrade, later ones deploy fully
      |> stub(:check, fn check ->
        called = Process.get(:checks, 0)
        Process.put(:checks, called + 1)
        {:ok, %{check | deploy: if(called == 0, do: :hot_upgrade, else: :full_deployment)}}
      end)
      |> expect(:execute, 0, fn _execute -> :ok end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 500,
                   deploy_schedule_interval_ms: 50,
                   name: name,
                   language: "elixir"
                 })

        assert_receive :requested, 1_000

        # the instance moves on while its command hangs
        :sys.replace_state(worker, fn state ->
          %{
            state
            | deployments: Map.update!(state.deployments, 1, &%{&1 | sname: "myelixir-other"})
          }
        end)

        assert_receive :cancelled, 2_000
      end
    end

    test "A monitor that stays busy until the timeout falls back to a full deployment" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      # no pre_command ran, so the release is not ghosted
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      # the start-up deployment, then the fallback full deployment
      |> expect(:start_service, 2, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> stub(:start_pre_commands, fn _sname, ["eval Migrate.run"], :new ->
        send(pid, :requested)
        reply_pre_commands({:error, :busy})
      end)
      # a request the monitor takes after the timeout is stopped at once
      |> expect(:cancel_pre_commands, 1, fn _sname, _ref -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      |> expect(:execute, 0, fn _execute -> :ok end)

      log =
        capture_log(fn ->
          with_mock System, [:passthrough],
            cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
            assert {:ok, _worker} =
                     Engine.Worker.start_link(%Engine.Worker{
                       deploy_rollback_timeout_ms: 500,
                       deploy_schedule_interval_ms: 50,
                       name: "myelixir",
                       language: "elixir"
                     })

            assert_receive {:started, sname}, 1_000
            Engine.notify_application_running(sname)

            assert_receive :requested, 1_000
            assert_receive :requested, 1_000
            assert_receive {:started, new_sname}, 2_000
            assert new_sname != sname
          end
        end)

      assert log =~ "did not start the pre-commands within 500 ms, deploying fully"
    end

    test "A monitor that never starts the run falls back to a full deployment, no ghost" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      # the start-up deployment, then the fallback full deployment
      |> expect(:start_service, 2, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      # the cast stays in the monitor's mailbox: no started message and no result
      |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
        {:ok, make_ref()}
      end)
      |> expect(:cancel_pre_commands, 1, fn _sname, _ref -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      |> expect(:execute, 0, fn _execute -> :ok end)

      log =
        capture_log(fn ->
          with_mock System, [:passthrough],
            cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
            assert {:ok, _worker} =
                     Engine.Worker.start_link(%Engine.Worker{
                       deploy_rollback_timeout_ms: 500,
                       deploy_schedule_interval_ms: 50,
                       name: "myelixir",
                       language: "elixir"
                     })

            assert_receive {:started, sname}, 1_000
            Engine.notify_application_running(sname)

            assert_receive {:started, new_sname}, 2_000
            assert new_sname != sname
          end
        end)

      assert log =~ "did not start the pre-commands within 500 ms, deploying fully"
    end

    test "Time spent waiting on a busy monitor does not shorten the run" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        if Process.get(:upgraded), do: "2.0.0", else: "1.0.0"
      end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> expect(:stop_service, 1, fn _name, nil -> :ok end)
      # busy for most of the 600 ms timeout, then a run that takes 400 ms
      |> stub(:start_pre_commands, fn _sname, ["eval Migrate.run"], :new ->
        first = Process.get(:first_request) || System.monotonic_time(:millisecond)
        Process.put(:first_request, first)

        if System.monotonic_time(:millisecond) - first < 400 do
          reply_pre_commands({:error, :busy})
        else
          ref = make_ref()
          send(self(), {:pre_commands_started, ref})

          Process.send_after(
            self(),
            {:pre_commands_result, ref, {:ok, ["eval Migrate.run"]}},
            400
          )

          {:ok, ref}
        end
      end)
      |> expect(:cancel_pre_commands, 0, fn _sname, _ref -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      |> expect(:execute, 1, fn _execute ->
        Process.put(:upgraded, true)
        send(pid, :upgraded)
        :ok
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _worker} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 600,
                   deploy_schedule_interval_ms: 50,
                   name: "myelixir",
                   language: "elixir"
                 })

        assert_receive {:started, sname}, 1_000
        Engine.notify_application_running(sname)

        assert_receive :upgraded, 3_000
      end
    end

    test "Pre-commands that ran before the app went down are not run again" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        if Process.get(:upgraded), do: "2.0.0", else: "1.0.0"
      end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> expect(:stop_service, 1, fn _name, nil -> :ok end)
      # the list runs once, the retry only waits for the app with an empty list
      |> expect(:start_pre_commands, 2, fn
        _sname, ["eval Migrate.run"], :new -> reply_pre_commands({:error, :app_down})
        _sname, [], :new -> reply_pre_commands({:ok, []})
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      |> expect(:execute, 1, fn _execute ->
        Process.put(:upgraded, true)
        send(pid, :upgraded)
        :ok
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _worker} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 50,
                   name: "myelixir",
                   language: "elixir"
                 })

        assert_receive {:started, sname}, 1_000
        Engine.notify_application_running(sname)

        assert_receive :upgraded, 2_000
      end
    end

    test "An app that stays down after its pre-commands falls back to a full deployment" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      # the start-up deployment, then the fallback full deployment
      |> expect(:start_service, 2, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
        reply_pre_commands({:error, :app_down})
      end)
      |> stub(:start_pre_commands, fn _sname, [], :new -> reply_pre_commands({:error, :busy}) end)
      |> expect(:cancel_pre_commands, 1, fn _sname, _ref -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "2.0.0", hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      |> expect(:execute, 0, fn _execute -> :ok end)

      log =
        capture_log(fn ->
          with_mock System, [:passthrough],
            cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
            assert {:ok, _worker} =
                     Engine.Worker.start_link(%Engine.Worker{
                       deploy_rollback_timeout_ms: 500,
                       deploy_schedule_interval_ms: 50,
                       name: "myelixir",
                       language: "elixir"
                     })

            assert_receive {:started, sname}, 1_000
            Engine.notify_application_running(sname)

            assert_receive {:started, new_sname}, 2_000
            assert new_sname != sname
          end
        end)

      assert log =~ "did not run again within 500 ms after its pre-commands, deploying fully"
    end

    test "A version map that moves on during the pre-commands is not installed" do
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:add_ghosted_version, 0, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      |> stub(:start_service, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      # the operator publishes 3.0.0 while the 2.0.0 migration runs
      |> expect(:start_pre_commands, 1, fn _sname, ["eval Migrate.run"], :new ->
        Process.put(:moved_on, true)
        reply_pre_commands({:ok, ["eval Migrate.run"]})
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        version = if Process.get(:moved_on), do: "3.0.0", else: "2.0.0"
        %{version: version, hash: "local", pre_commands: ["eval Migrate.run"]}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      # the first check offers a hot upgrade, the next one (for 3.0.0) deploys fully
      |> stub(:check, fn check ->
        called = Process.get(:checks, 0)
        Process.put(:checks, called + 1)
        {:ok, %{check | deploy: if(called == 0, do: :hot_upgrade, else: :full_deployment)}}
      end)
      |> expect(:execute, 0, fn _execute -> :ok end)

      log =
        capture_log(fn ->
          with_mock System, [:passthrough],
            cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
            assert {:ok, _worker} =
                     Engine.Worker.start_link(%Engine.Worker{
                       deploy_rollback_timeout_ms: 60_000,
                       deploy_schedule_interval_ms: 50,
                       name: "myelixir",
                       language: "elixir"
                     })

            assert_receive {:started, sname}, 1_000
            Engine.notify_application_running(sname)

            # the next deployment is for 3.0.0
            assert_receive {:started, _new_sname}, 2_000
          end
        end)

      assert log =~ "The version changed while the pre-commands ran"
    end

    test "A DOWN the worker is not waiting for is ignored" do
      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> nil end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: nil, hash: nil, pre_commands: []}
      end)

      assert {:ok, worker} =
               Engine.Worker.start_link(%Engine.Worker{
                 deploy_rollback_timeout_ms: 60_000,
                 deploy_schedule_interval_ms: 60_000,
                 name: "myelixir",
                 language: "elixir"
               })

      # a monitor ref that code of the previous version set up during a relup
      send(worker, {:DOWN, make_ref(), :process, self(), :shutdown})

      assert %Engine.Worker{} = :sys.get_state(worker)
      assert Process.alive?(worker)
    end

    test "A worker that a relup could not update takes a restart before its next check" do
      name = "myelixir"
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> stub(:start_service, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "1.0.0", hash: "local", pre_commands: []}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> stub(:check, fn check -> {:ok, %{check | deploy: :full_deployment}} end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   # no scheduled check lands during the test
                   deploy_schedule_interval_ms: 60_000,
                   name: name,
                   language: "elixir"
                 })

        :sys.replace_state(worker, &Map.delete(&1, :pending_pre_commands))

        Engine.Worker.restart_deployments(name)
        Engine.Worker.updated_state_values(name, %{replicas: 1})

        assert Process.alive?(worker)
        assert %{replicas: 1} = :sys.get_state(worker)
      end
    end

    test "A worker restarted with a state built by an older version runs" do
      name = "myelixir"
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> "1.0.0" end)
      |> stub(:update, fn _sname -> :ok end)
      |> stub(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> stub(:start_service, fn service ->
        send(pid, {:started, service.sname})
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: "1.0.0", hash: "local", pre_commands: []}
      end)
      |> stub(:download_release, fn _app_name, _version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> stub(:check, fn check -> {:ok, %{check | deploy: :full_deployment}} end)

      # the supervisor restarts a worker with the start argument the old code built
      old_start_arg =
        Map.delete(
          %Engine.Worker{
            deploy_rollback_timeout_ms: 60_000,
            deploy_schedule_interval_ms: 50,
            name: name,
            language: "elixir"
          },
          :pending_pre_commands
        )

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        # what Engine.Worker.start_link/1 does, without the struct type on the argument
        assert {:ok, worker} =
                 GenServer.start_link(Engine.Worker, old_start_arg, name: String.to_atom(name))

        assert_receive {:started, sname}, 1_000
        Engine.notify_application_running(sname)

        # several schedule ticks read the field
        Process.sleep(300)

        assert Process.alive?(worker)
        assert %Engine.Worker{pending_pre_commands: nil} = :sys.get_state(worker)
      end
    end

    test "code_change adds the pending pre-commands field to a state from an older version" do
      old_state = Map.delete(%Engine.Worker{name: "myelixir"}, :pending_pre_commands)

      assert {:ok, %Engine.Worker{name: "myelixir", pending_pre_commands: nil}} =
               Engine.Worker.code_change("0.10.0", old_state, [])
    end
  end

  describe "Deployment Status" do
    @tag :capture_log
    test "Check deployment succeed and move to the next instance" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First 2 calls are the starting process and update
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          to_version
        else
          from_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn %{sname: sname} ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref, sname})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, 2, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language,
                   replicas: 3
                 })

        assert_receive {:handle_ref_event, ^ref, sname}, 1_000

        module_name = String.to_atom(name)
        _state = :sys.get_state(module_name)
        Engine.notify_application_running(sname)
        state = :sys.get_state(module_name)

        assert state.current == 2
      end
    end

    @tag :capture_log
    test "Check deployment won't move to the next instance with invalid notification" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      test_event_ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First 2 calls are the starting process and update,
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          "2.0.0"
        else
          from_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _service ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, test_event_ref})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 1 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

        module_name = String.to_atom(name)
        _state = :sys.get_state(module_name)
        # Send multiple invalid data combination
        Engine.notify_application_running("invalid_name-99")
        Engine.notify_application_running("invalid_name-1")
        Engine.notify_application_running("invalid_name-99")
        state = :sys.get_state(module_name)

        assert state.current == 1
      end
    end

    test "Deployment error while trying to download" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      test_event_ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First 2 calls are the starting process and update,
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          "2.0.0"
        else
          from_version
        end
      end)
      |> expect(:update, 1, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 1, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _service ->
        {:ok, self()}
      end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> stub(:download_release, fn _app_name, version, _download_path
                                    when version in [from_version, to_version] ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_release", 0)
        Process.put("download_release", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, test_event_ref})
          {:error, :any}
        else
          :ok
        end
      end)

      Deployer.HotUpgradeMock
      |> expect(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

      assert capture_log(fn ->
               with_mock System, [:passthrough],
                 cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
                 assert {:ok, _pid} =
                          Engine.Worker.start_link(%Engine.Worker{
                            deploy_rollback_timeout_ms: 1_000,
                            deploy_schedule_interval_ms: 100,
                            name: name,
                            language: language
                          })

                 assert_receive {:handle_ref_event, ^test_event_ref}, 1_000

                 module_name = String.to_atom(name)
                 state = :sys.get_state(module_name)

                 assert state.current == 1
               end
             end) =~ " Download and unpack error: {:error, :any} current_sname:"
    end
  end

  describe "Deployment manual version" do
    @tag :capture_log
    test "Configure Manual version from automatic" do
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()

      automatic_version = "2.0.0"
      manual_version = "1.0.0"
      manual_version_map = %{version: manual_version, hash: "local", pre_commands: []}

      Catalog.config_update("myelixir", %{
        Catalog.config("myelixir")
        | mode: :manual,
          manual_version: manual_version_map
      })

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First time: initialization version
        # Second time: check_deployment
        # Third time: manual deployment done
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          manual_version
        else
          automatic_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _service ->
        # First time: initialization
        # Second time: start manual version
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: automatic_version, hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [manual_version, automatic_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^automatic_version,
                                to_version: ^manual_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 30_000,
                   deploy_schedule_interval_ms: 200,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end

    @tag :capture_log
    test "Configure Automatic version from manual" do
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()

      automatic_version = "2.0.0"

      automatic_version_map = %{
        version: automatic_version,
        hash: "local",
        pre_commands: []
      }

      manual_version = "1.0.0"

      Catalog.config_update("myelixir", %{
        Catalog.config("myelixir")
        | mode: :automatic,
          manual_version: nil
      })

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First time: initialization version
        # Second time: check_deployment
        # Third time: automatic deployment done
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          automatic_version
        else
          manual_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _service ->
        # First time: initialization
        # Second time: start manual version
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name -> automatic_version_map end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [automatic_version, manual_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^manual_version,
                                to_version: ^automatic_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 30_000,
                   deploy_schedule_interval_ms: 200,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end
  end

  describe "Deployment complete notification" do
    @tag :capture_log
    test "a full deployment reports the version it deployed" do
      name = "myelixir"
      sname = Catalog.create_sname(name)

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn ^sname -> "1.1.0" end)

      Deployer.MonitorMock
      |> stub(:stop_service, fn _name, _sname -> :ok end)

      subscribe_to_deployment_complete()

      pid = start_worker(name)
      running_deployment(pid, sname, deploying?: true, terminating?: true)

      GenServer.cast(pid, {:application_running, sname})

      # the message is what every adapter renders, the payload key is there for the ones
      # that forward structured data
      assert_receive {"deployment_complete", payload}, 1_000
      assert payload.status == :ok
      assert payload.message == "Full deployment applied successfully, version 1.1.0"
      assert payload.version == "1.1.0"
    end

    @tag :capture_log
    test "a version put into service at start up is reported as well" do
      name = "myelixir"
      sname = Catalog.create_sname(name)

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn ^sname -> "1.1.0" end)

      subscribe_to_deployment_complete()

      pid = start_worker(name)

      # initialize_version/1 puts a version into service without a previous deployment to
      # terminate, so the flag is set and there is nothing to stop afterwards
      running_deployment(pid, sname, deploying?: true, terminating?: false)

      GenServer.cast(pid, {:application_running, sname})

      assert_receive {"deployment_complete", payload}, 1_000
      assert payload.message == "Full deployment applied successfully, version 1.1.0"
    end

    @tag :capture_log
    test "a report with nothing waiting for it is not announced as a deployment" do
      name = "myelixir"
      sname = Catalog.create_sname(name)

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn ^sname -> "1.1.0" end)

      subscribe_to_deployment_complete()

      pid = start_worker(name)
      running_deployment(pid, sname, deploying?: false, terminating?: false)

      GenServer.cast(pid, {:application_running, sname})

      # a crash restart, a restart asked for from the UI and a hot upgrade all report an
      # application running with nothing waiting for it, and the hot upgrade has already
      # sent its own notification with the versions it moved between
      refute_receive {"deployment_complete", _payload}, 300
    end

    @tag :capture_log
    test "a hot upgrade does not close a window the start up left open" do
      # Monitors live in a separate supervision tree, so an engine worker restart while the
      # monitor still starts the application arms the rollback window. The hot upgrade that
      # follows must not take that window
      name = "myelixir"
      sname = Catalog.create_sname(name)
      FixtureFiles.create_bin_files(sname)

      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      test_pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: from_version}]
      end)
      |> stub(:current_version, fn _sname ->
        # 0 -> initialize_version, 1 -> check_deployment, 2 -> hot upgrade,
        # 3 -> the upgrade result, which is what says the upgrade succeeded
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2, do: to_version, else: from_version
      end)
      |> stub(:update, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 1, fn _sname, _release, deployment: :hot_upgrade ->
        send(test_pid, {:handle_ref_event, ref})
        :ok
      end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn %{sname: ^sname} -> {:error, {:already_started, self()}} end)
      |> stub(:state, fn ^sname ->
        %Deployer.Monitor{sname: sname, current_pid: self(), status: :starting}
      end)
      # no pre_commands, so the monitor is not asked to run any
      |> expect(:start_pre_commands, 0, fn _sname, _release, :new -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: to_version, hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, 1, fn _app_name, ^to_version, _download_path -> :ok end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn check -> {:ok, %{check | deploy: :hot_upgrade}} end)
      |> expect(:execute, 1, fn %Deployer.HotUpgrade.Execute{to_version: ^to_version} -> :ok end)

      subscribe_to_deployment_complete()

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 60_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: "elixir"
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000

        # the upgrade reported itself with the versions it moved between, and the window
        # the start up left open must not turn the report it triggers into a full
        # deployment of 2.0.0
        refute_receive {"deployment_complete", _payload}, 300
      end
    end

    @tag :capture_log
    test "the same deployment is not reported twice" do
      name = "myelixir"
      sname = Catalog.create_sname(name)

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn ^sname -> "1.1.0" end)

      Deployer.MonitorMock
      |> stub(:stop_service, fn _name, _sname -> :ok end)

      subscribe_to_deployment_complete()

      pid = start_worker(name)
      running_deployment(pid, sname, deploying?: true, terminating?: true)

      GenServer.cast(pid, {:application_running, sname})
      assert_receive {"deployment_complete", _payload}, 1_000

      # the application reporting running again, e.g. after a crash restart, finds the
      # deployment already completed
      GenServer.cast(pid, {:application_running, sname})
      refute_receive {"deployment_complete", _payload}, 300

      assert %Deployer.Engine.Deployment{timer_ref: nil, deploying?: false} =
               :sys.get_state(pid).deployments[1]
    end

    defp subscribe_to_deployment_complete do
      Phoenix.PubSub.subscribe(
        Foundation.PubSub,
        Foundation.Notifications.topic("deployment_complete")
      )
    end

    defp start_worker(name) do
      assert {:ok, pid} =
               Engine.Worker.start_link(%Engine.Worker{
                 deploy_rollback_timeout_ms: 60_000,
                 deploy_schedule_interval_ms: 60_000,
                 name: name,
                 language: "elixir"
               })

      pid
    end

    # deploying? is set where a version is put into service, and a full deployment is the
    # case that also leaves a previous deployment waiting to be terminated
    defp running_deployment(pid, sname, deploying?: deploying?, terminating?: terminating?) do
      :sys.replace_state(pid, fn state ->
        deployment = %{
          state.deployments[state.current]
          | sname: sname,
            state: :active,
            timer_ref: Process.send_after(pid, :ignored, 60_000),
            deploying?: deploying?
        }

        %{
          state
          | deployments: Map.put(state.deployments, state.current, deployment),
            deployment_to_terminate: if(terminating?, do: %Deployer.Engine.Deployment{})
        }
      end)
    end
  end

  describe "Application ready notification" do
    @tag :capture_log
    test "a report that is not a deployment is still announced as ready" do
      name = "myelixir"
      sname = Catalog.create_sname(name)

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn ^sname -> "1.1.0" end)

      subscribe_to_application_ready()
      subscribe_to_deployment_complete()

      pid = start_worker(name)
      running_deployment(pid, sname, deploying?: false, terminating?: false)

      GenServer.cast(pid, {:application_running, sname})

      # a crash restart and a restart asked for from the UI put the application back into
      # service without deploying anything, and this is the event that reports them
      assert_receive {"application_ready", payload}, 1_000
      assert payload.sname == sname
      assert payload.node == node()
      assert payload.version == "1.1.0"

      refute_receive {"deployment_complete", _payload}, 300
    end

    @tag :capture_log
    test "a deployment is announced as ready as well as complete" do
      name = "myelixir"
      sname = Catalog.create_sname(name)

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn ^sname -> "1.1.0" end)

      Deployer.MonitorMock
      |> stub(:stop_service, fn _name, _sname -> :ok end)

      subscribe_to_application_ready()
      subscribe_to_deployment_complete()

      pid = start_worker(name)
      running_deployment(pid, sname, deploying?: true, terminating?: true)

      GenServer.cast(pid, {:application_running, sname})

      assert_receive {"deployment_complete", _payload}, 1_000
      assert_receive {"application_ready", %{version: "1.1.0"}}, 1_000
    end

    defp subscribe_to_application_ready do
      Phoenix.PubSub.subscribe(
        Foundation.PubSub,
        Foundation.Notifications.topic("application_ready")
      )
    end
  end

  describe "Ghosted version list" do
    @tag :capture_log
    test "The worker takes the new list from the broadcast" do
      name = "myelixir"
      ghosted = %Foundation.Catalog.Version{version: "2.0.0", name: name}

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> expect(:ghosted_version_list, 1, fn ^name -> [ghosted] end)

      assert {:ok, pid} =
               Engine.Worker.start_link(%Engine.Worker{
                 deploy_rollback_timeout_ms: 60_000,
                 deploy_schedule_interval_ms: 60_000,
                 name: name,
                 language: "elixir"
               })

      # read on start up, not handed in by whoever started the worker
      assert :sys.get_state(pid).ghosted_version_list == [ghosted]

      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        "deployex::ghosted_versions::#{name}",
        {:ghosted_versions_updated, Node.self(), name, []}
      )

      # the worker consults its own copy on every deployment check, so that is what has to
      # end up changed
      # :sys.get_state queues behind the broadcast the worker was just sent, so by the time
      # it replies the message has been handled
      assert :sys.get_state(pid).ghosted_version_list == []
    end

    @tag :capture_log
    test "A change made while the worker starts up is not lost" do
      name = "myelixir"
      ghosted = %Foundation.Catalog.Version{version: "2.0.0", name: name}
      test_pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      # stands in for a change landing between the subscribe and the read. Subscribing first
      # is what turns it into a message the worker still gets, rather than a lost update
      |> expect(:subscribe_ghosted_versions, fn ^name ->
        :ok = Phoenix.PubSub.subscribe(Deployer.PubSub, "deployex::ghosted_versions::#{name}")

        Phoenix.PubSub.broadcast(
          Deployer.PubSub,
          "deployex::ghosted_versions::#{name}",
          {:ghosted_versions_updated, Node.self(), name, [ghosted]}
        )

        send(test_pid, :subscribed)
        :ok
      end)
      |> expect(:ghosted_version_list, 1, fn ^name -> [] end)

      assert {:ok, pid} =
               Engine.Worker.start_link(%Engine.Worker{
                 deploy_rollback_timeout_ms: 60_000,
                 deploy_schedule_interval_ms: 60_000,
                 name: name,
                 language: "elixir"
               })

      assert_receive :subscribed

      # the read returned the list from before the change, the message carries the change
      assert :sys.get_state(pid).ghosted_version_list == [ghosted]
    end

    @tag :capture_log
    test "The worker ignores a change made on another node" do
      name = "myelixir"
      ghosted = %Foundation.Catalog.Version{version: "2.0.0", name: name}

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> expect(:ghosted_version_list, 1, fn ^name -> [ghosted] end)

      assert {:ok, pid} =
               Engine.Worker.start_link(%Engine.Worker{
                 deploy_rollback_timeout_ms: 60_000,
                 deploy_schedule_interval_ms: 60_000,
                 name: name,
                 language: "elixir"
               })

      # read on start up, not handed in by whoever started the worker
      assert :sys.get_state(pid).ghosted_version_list == [ghosted]

      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        "deployex::ghosted_versions::#{name}",
        {:ghosted_versions_updated, :other@node, name, []}
      )

      # the ghosted list is stored by the instance that owns the application, another node
      # changing its own says nothing about this one
      assert :sys.get_state(pid).ghosted_version_list == [ghosted]
    end
  end

  describe "Deployment rollback" do
    @tag :capture_log
    test "Rollback a version after timeout" do
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()
      version_to_rollback = "1.0.0"
      version_to_ghost = "2.0.0"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> version_to_ghost end)
      |> expect(:update, fn _sname -> :ok end)
      |> expect(:set_current_version_map, fn _sname, _release, _attrs -> :ok end)
      |> expect(:current_version_map, 1, fn _sname ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:add_ghosted_version, 1, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      |> expect(:start_service, fn _service ->
        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname ->
        send(pid, {:handle_ref_event, ref})
        :ok
      end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, fn _app_name, version, _download_path
                                      when version in [version_to_ghost, version_to_rollback] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 50,
                   deploy_schedule_interval_ms: 200,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000

        module_name = String.to_atom(name)
        state = :sys.get_state(module_name)
        assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
        assert state.current == 1
      end
    end

    @tag :capture_log
    test "Rollback after timeout on initial boot keeps the engine alive" do
      # When the engine initializes with an installed application, the rollback
      # timer is armed without a previous deployment to terminate. If the
      # application never reports running, the rollback must reset the instance
      # to an empty deployment instead of corrupting the state.
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()
      sname = Catalog.create_sname("myelixir")
      FixtureFiles.create_bin_files(sname)
      version_to_ghost = "1.2.3"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> stub(:current_version, fn _sname -> version_to_ghost end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: version_to_ghost}]
      end)
      |> expect(:current_version_map, 1, fn _sname ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:add_ghosted_version, 1, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn %{sname: ^sname} -> {:ok, self()} end)
      |> expect(:stop_service, fn _name, ^sname ->
        send(pid, {:handle_ref_event, ref})
        :ok
      end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, worker_pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 100,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000

        # Let the engine run a few schedule cycles after the rollback
        :timer.sleep(300)

        assert Process.alive?(worker_pid)

        state = :sys.get_state(String.to_atom(name))
        assert %Deployer.Engine.Deployment{sname: nil} = state.deployments[1]
        assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
      end
    end

    @tag :capture_log
    test "Invalid rollback message" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First 2 calls are the starting process and update
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          to_version
        else
          from_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn _service ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref})
        end

        {:ok, self()}
      end)
      |> expect(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000

        module_name = String.to_atom(name)
        _state = :sys.get_state(module_name)

        send(pid, {:timeout_rollback, 1, make_ref()})
        state = :sys.get_state(module_name)

        assert state.current == 1
      end
    end

    test "Rolling back a version" do
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()
      version_to_ghost = "2.0.0"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname -> version_to_ghost end)
      |> expect(:update, 1, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 1, fn _sname, _release, _attrs -> :ok end)
      |> expect(:current_version_map, 1, fn _sname ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:add_ghosted_version, 1, fn version_map -> {:ok, [version_map]} end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _service -> {:ok, self()} end)
      |> expect(:stop_service, fn _name, _sname ->
        send(pid, {:handle_ref_event, ref})
        :ok
      end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> stub(:download_release, fn _app_name, ^version_to_ghost, _download_path ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> expect(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

      logs =
        capture_log(fn ->
          with_mock System, [:passthrough],
            cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
            assert {:ok, _pid} =
                     Engine.Worker.start_link(%Engine.Worker{
                       deploy_rollback_timeout_ms: 50,
                       deploy_schedule_interval_ms: 200,
                       name: name,
                       language: language,
                       replica_ports: [%{key: "PORT1", base: 1}]
                     })

            assert_receive {:handle_ref_event, ^ref}, 1_000

            module_name = String.to_atom(name)
            state = :sys.get_state(module_name)
            assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
            assert state.current == 1
          end
        end)

      assert logs =~ "base: 2"
      assert logs =~ "key: \"PORT1\""
      assert logs =~ "is not stable, ghosting version"
    end
  end

  describe "Config updates" do
    @tag :capture_log
    test "Check restart deployments requested" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First 2 calls are the starting process and update
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          to_version
        else
          from_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn %{sname: sname} ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref, sname})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language,
                   replicas: 3
                 })

        assert_receive {:handle_ref_event, ^ref, _sname}, 1_000

        module_name = String.to_atom(name)
        _state = :sys.get_state(module_name)

        Engine.Worker.restart_deployments(name)
        # Check the State is fully restarted and ready to deploy again
        assert %Deployer.Engine.Worker{
                 replicas: 3,
                 current: 1,
                 deployments: %{
                   1 => %Deployer.Engine.Deployment{
                     ports: [],
                     state: :init,
                     sname: nil,
                     timer_ref: nil
                   },
                   2 => %Deployer.Engine.Deployment{
                     ports: [],
                     state: :init,
                     sname: nil,
                     timer_ref: nil
                   },
                   3 => %Deployer.Engine.Deployment{
                     ports: [],
                     state: :init,
                     sname: nil,
                     timer_ref: nil
                   }
                 },
                 deployment_to_terminate: nil
               } = :sys.get_state(module_name)
      end
    end

    @tag :capture_log
    test "Update value" do
      name = "myelixir"
      language = "elixir"

      ref = make_ref()
      pid = self()
      sname = Catalog.create_sname("myelixir")
      FixtureFiles.create_bin_files(sname)
      version = "1.2.3"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [sname] end)
      |> expect(:current_version, 2, fn _sname -> version end)
      |> expect(:history_version_list, fn _name, _options ->
        [%Catalog.Version{version: version}]
      end)

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn %{sname: ^sname} ->
        send(pid, {:handle_ref_event, ref})
        {:ok, self()}
      end)

      Deployer.ReleaseMock
      |> expect(:download_version_map, 0, fn _app_name -> nil end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   deploy_rollback_timeout_ms: 1_000,
                   deploy_schedule_interval_ms: 100,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000

        module_name = String.to_atom(name)

        Engine.Worker.updated_state_values(name, %{deploy_rollback_timeout_ms: 5_000})

        assert %Deployer.Engine.Worker{deploy_rollback_timeout_ms: 5_000} =
                 :sys.get_state(module_name)

        Engine.Worker.updated_state_values(name, %{language: "gleam"})
        assert %Deployer.Engine.Worker{language: "gleam"} = :sys.get_state(module_name)

        Engine.Worker.updated_state_values(name, %{deploy_schedule_interval_ms: 5_000})

        assert %Deployer.Engine.Worker{deploy_schedule_interval_ms: 5_000} =
                 :sys.get_state(module_name)

        Engine.Worker.updated_state_values(name, %{env: ["any=abc"]})
        assert %Deployer.Engine.Worker{env: ["any=abc"]} = :sys.get_state(module_name)
      end
    end

    @tag :capture_log
    test "Check Add replicas (Without replica_ports)" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First 2 calls are the starting process and update
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          to_version
        else
          from_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn %{sname: sname} ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref, sname})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      assert capture_log(fn ->
               with_mock System, [:passthrough],
                 cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
                 assert {:ok, _pid} =
                          Engine.Worker.start_link(%Engine.Worker{
                            deploy_rollback_timeout_ms: 1_000,
                            deploy_schedule_interval_ms: 100,
                            name: name,
                            language: language,
                            replicas: 3
                          })

                 assert_receive {:handle_ref_event, ^ref, sname}, 1_000

                 module_name = String.to_atom(name)
                 _state = :sys.get_state(module_name)

                 Engine.notify_application_running(sname)

                 Engine.Worker.updated_state_values(name, %{replicas: 5})
                 # Check the State is fully restarted and ready to deploy again
                 assert %Deployer.Engine.Worker{
                          replicas: 5,
                          current: 4,
                          deployments: %{
                            1 => %Deployer.Engine.Deployment{
                              ports: [],
                              sname: _sname,
                              state: :active,
                              timer_ref: _timer_ref
                            },
                            2 => %Deployer.Engine.Deployment{
                              ports: [],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            },
                            3 => %Deployer.Engine.Deployment{
                              ports: [],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            },
                            4 => %Deployer.Engine.Deployment{
                              ports: [],
                              state: :init,
                              sname: nil,
                              timer_ref: nil
                            },
                            5 => %Deployer.Engine.Deployment{
                              ports: [],
                              state: :init,
                              sname: nil,
                              timer_ref: nil
                            }
                          },
                          deployment_to_terminate: nil
                        } = :sys.get_state(module_name)
               end
             end) =~ "Adding new replicas for myelixir"
    end

    @tag :capture_log
    test "Check Add replicas (With replica_ports)" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First 2 calls are the starting process and update
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          to_version
        else
          from_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn %{sname: sname} ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref, sname})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      assert capture_log(fn ->
               with_mock System, [:passthrough],
                 cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
                 assert {:ok, _pid} =
                          Engine.Worker.start_link(%Engine.Worker{
                            deploy_rollback_timeout_ms: 1_000,
                            deploy_schedule_interval_ms: 100,
                            name: name,
                            language: language,
                            replicas: 3,
                            replica_ports: [%{key: "PORT", base: 6000}]
                          })

                 assert_receive {:handle_ref_event, ^ref, sname}, 1_000

                 module_name = String.to_atom(name)
                 _state = :sys.get_state(module_name)

                 Engine.notify_application_running(sname)

                 Engine.Worker.updated_state_values(name, %{replicas: 5})
                 # Check the State is fully restarted and ready to deploy again
                 assert %Deployer.Engine.Worker{
                          replicas: 5,
                          current: 4,
                          deployments: %{
                            1 => %Deployer.Engine.Deployment{
                              ports: [%{base: 6003, key: "PORT"}],
                              sname: _sname,
                              state: :active,
                              timer_ref: _timer_ref
                            },
                            2 => %Deployer.Engine.Deployment{
                              ports: [%{base: 6001, key: "PORT"}],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            },
                            3 => %Deployer.Engine.Deployment{
                              ports: [%{base: 6002, key: "PORT"}],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            },
                            4 => %Deployer.Engine.Deployment{
                              ports: [%{base: 6004, key: "PORT"}],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            },
                            5 => %Deployer.Engine.Deployment{
                              ports: [%{base: 6005, key: "PORT"}],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            }
                          },
                          deployment_to_terminate: nil
                        } = :sys.get_state(module_name)
               end
             end) =~ "Adding new replicas for myelixir"
    end

    @tag :capture_log
    test "Check Remove replicas (With replica_ports)" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First 2 calls are the starting process and update
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          to_version
        else
          from_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn %{sname: sname} ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref, sname})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      assert capture_log(fn ->
               with_mock System, [:passthrough],
                 cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
                 assert {:ok, _pid} =
                          Engine.Worker.start_link(%Engine.Worker{
                            deploy_rollback_timeout_ms: 1_000,
                            deploy_schedule_interval_ms: 100,
                            name: name,
                            language: language,
                            replicas: 3,
                            replica_ports: [%{key: "PORT", base: 6000}]
                          })

                 assert_receive {:handle_ref_event, ^ref, sname}, 1_000

                 module_name = String.to_atom(name)
                 _state = :sys.get_state(module_name)

                 Engine.notify_application_running(sname)

                 Engine.Worker.updated_state_values(name, %{replicas: 2})
                 # Check the State is fully restarted and ready to deploy again
                 assert %Deployer.Engine.Worker{
                          replicas: 2,
                          current: 1,
                          deployments: %{
                            1 => %Deployer.Engine.Deployment{
                              ports: [%{base: 6003, key: "PORT"}],
                              sname: _sname,
                              state: :active,
                              timer_ref: _timer_ref
                            },
                            2 => %Deployer.Engine.Deployment{
                              ports: [%{base: 6001, key: "PORT"}],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            }
                          },
                          deployment_to_terminate: nil
                        } = :sys.get_state(module_name)
               end
             end) =~ "Removing replicas for myelixir"
    end

    test "Check Change replica ports (it forces to restart the deployment)" do
      name = "myelixir"
      language = "elixir"
      from_version = "1.0.0"
      to_version = "2.0.0"
      ref = make_ref()
      pid = self()

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)
      |> stub(:current_version, fn _sname ->
        # First 2 calls are the starting process and update
        # the next ones should be the new version
        called = Process.get("current_version", 0)
        Process.put("current_version", called + 1)

        if called > 2 do
          to_version
        else
          from_version
        end
      end)
      |> expect(:update, 2, fn _sname -> :ok end)
      |> expect(:set_current_version_map, 2, fn _sname, _release, _attrs -> :ok end)

      Deployer.MonitorMock
      |> expect(:start_service, 2, fn %{sname: sname} ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("start_service", 0)
        Process.put("start_service", called + 1)

        if called > 0 do
          send(pid, {:handle_ref_event, ref, sname})
        end

        {:ok, self()}
      end)
      |> stub(:stop_service, fn _name, _sname -> :ok end)
      |> expect(:start_pre_commands, 0, fn _sname, _release, _type -> {:ok, make_ref()} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        # First time: initialization
        # Second time: new deployment
        called = Process.get("download_version_map", 0)
        Process.put("download_version_map", called + 1)

        if called > 0 do
          %{version: to_version, hash: "local", pre_commands: []}
        else
          %{version: from_version, hash: "local", pre_commands: []}
        end
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [from_version, to_version] ->
        :ok
      end)

      Deployer.HotUpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.HotUpgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } = check ->
        {:ok, %{check | deploy: :full_deployment}}
      end)

      assert capture_log(fn ->
               with_mock System, [:passthrough],
                 cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
                 assert {:ok, _pid} =
                          Engine.Worker.start_link(%Engine.Worker{
                            deploy_rollback_timeout_ms: 1_000,
                            deploy_schedule_interval_ms: 100,
                            name: name,
                            language: language,
                            replicas: 3,
                            replica_ports: [%{key: "PORT", base: 6000}]
                          })

                 assert_receive {:handle_ref_event, ^ref, sname}, 1_000

                 module_name = String.to_atom(name)
                 _state = :sys.get_state(module_name)

                 Engine.notify_application_running(sname)

                 Engine.Worker.updated_state_values(name, %{
                   replica_ports: [%{base: 7000, key: "PORT"}]
                 })

                 # Check the State is fully restarted and ready to deploy again
                 assert %Deployer.Engine.Worker{
                          replicas: 3,
                          current: 2,
                          deployments: %{
                            1 => %Deployer.Engine.Deployment{
                              ports: [%{base: 7000, key: "PORT"}],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            },
                            2 => %Deployer.Engine.Deployment{
                              ports: [%{base: 7001, key: "PORT"}],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            },
                            3 => %Deployer.Engine.Deployment{
                              ports: [%{base: 7002, key: "PORT"}],
                              sname: nil,
                              state: :init,
                              timer_ref: nil
                            }
                          },
                          deployment_to_terminate: nil
                        } = :sys.get_state(module_name)
               end
             end) =~ "Updating replica ports for myelixir"
    end
  end

  # Monitor.Application answers a pre-commands request with a message to the caller, the
  # mock runs in the worker process, so self() is the worker
  defp reply_pre_commands(result) do
    ref = make_ref()
    send(self(), {:pre_commands_result, ref, result})
    {:ok, ref}
  end

  defp first_pre_commands_reply(:not_running), do: {:error, :not_running}

  # The monitor died between the lookup and the monitor call
  defp first_pre_commands_reply(:noproc) do
    {monitor, mref} = spawn_monitor(fn -> :ok end)
    receive do: ({:DOWN, ^mref, :process, _pid, _reason} -> :ok)
    {:ok, Process.monitor(monitor)}
  end

  # A monitor that crashes during the run, for a reason that has nothing to do with the release
  defp first_pre_commands_reply(:crashed) do
    monitor = spawn(fn -> receive do: (:crash -> exit(:crashed)) end)
    ref = Process.monitor(monitor)
    send(self(), {:pre_commands_started, ref})
    send(monitor, :crash)
    {:ok, ref}
  end

  defp pre_commands_reply(:failed), do: reply_pre_commands({:error, :pre_commands})

  # The run started and never ends
  defp pre_commands_reply(:no_reply) do
    ref = make_ref()
    send(self(), {:pre_commands_started, ref})
    {:ok, ref}
  end
end
