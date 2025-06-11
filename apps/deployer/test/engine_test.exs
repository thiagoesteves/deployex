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
    FixtureCatalog.cleanup()
  end

  describe "Initialization tests" do
    test "init/1" do
      name = "myelixir"
      language = "elixir"

      Deployer.StatusMock
      |> expect(:list_installed_apps, fn _name -> [] end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 1_000,
                   schedule_interval: 5_000,
                   name: name,
                   language: language
                 })

        assert {:error, {:already_started, _pid}} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 1_000,
                   schedule_interval: 5_000,
                   name: name,
                   language: language
                 })
      end
    end

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
                            timeout_rollback: 1_000,
                            schedule_interval: 10,
                            name: name,
                            language: language
                          })

                 assert_receive {:handle_ref_event, ^ref}, 1_000
               end
             end) =~ "No versions set yet for myelixir"
    end

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
                   timeout_rollback: 1_000,
                   schedule_interval: 10,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end
  end

  describe "Checking deployment" do
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
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

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

      Deployer.UpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.Upgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } ->
        {:ok, :full_deployment}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 1_000,
                   schedule_interval: 10,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end

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

      Deployer.MonitorMock
      |> expect(:start_service, 1, fn _service ->
        {:ok, self()}
      end)
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

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

      Deployer.UpgradeMock
      |> expect(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 1_000,
                   schedule_interval: 10,
                   name: name,
                   language: language,
                   ghosted_version_list: [%{version: ghosted_version}]
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end

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
      |> expect(:run_pre_commands, 1, fn _sname, _release, :new -> {:ok, []} end)

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

      Deployer.UpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.Upgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } ->
        {:ok, :hot_upgrade}
      end)
      |> expect(:execute, 1, fn %Deployer.Upgrade.Execute{
                                  from_version: ^from_version,
                                  to_version: ^to_version
                                } ->
        :ok
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 1_000,
                   schedule_interval: 10,
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
      |> stub(:run_pre_commands, fn _sname, _release, :new -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: to_version, hash: "local", pre_commands: []}
      end)
      |> stub(:download_release, fn _app_name, ^to_version, _download_path ->
        :ok
      end)

      Deployer.UpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.Upgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } ->
        {:ok, :hot_upgrade}
      end)
      |> expect(:execute, 1, fn %Deployer.Upgrade.Execute{
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
                            timeout_rollback: 1_000,
                            schedule_interval: 200,
                            name: name,
                            language: language
                          })

                 assert_receive {:handle_ref_event, ^ref}, 1_000
               end
             end) =~ "Hot Upgrade failed, running for full deployment"
    end
  end

  describe "Deployment Status" do
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
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

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

      Deployer.UpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.Upgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } ->
        {:ok, :full_deployment}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 1_000,
                   schedule_interval: 100,
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
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

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

      Deployer.UpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.Upgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } ->
        {:ok, :full_deployment}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 1_000,
                   schedule_interval: 100,
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
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

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

      Deployer.UpgradeMock
      |> expect(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

      assert capture_log(fn ->
               with_mock System, [:passthrough],
                 cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
                 assert {:ok, _pid} =
                          Engine.Worker.start_link(%Engine.Worker{
                            timeout_rollback: 1_000,
                            schedule_interval: 100,
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
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: automatic_version, hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [manual_version, automatic_version] ->
        :ok
      end)

      Deployer.UpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.Upgrade.Check{
                                from_version: ^automatic_version,
                                to_version: ^manual_version
                              } ->
        {:ok, :full_deployment}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 30_000,
                   schedule_interval: 200,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
    end

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
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name -> automatic_version_map end)
      |> expect(:download_release, 2, fn _app_name, version, _download_path
                                         when version in [automatic_version, manual_version] ->
        :ok
      end)

      Deployer.UpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.Upgrade.Check{
                                from_version: ^manual_version,
                                to_version: ^automatic_version
                              } ->
        {:ok, :full_deployment}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 30_000,
                   schedule_interval: 200,
                   name: name,
                   language: language
                 })

        assert_receive {:handle_ref_event, ^ref}, 1_000
      end
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
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> expect(:download_release, fn _app_name, version, _download_path
                                      when version in [version_to_ghost, version_to_rollback] ->
        :ok
      end)

      Deployer.UpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 50,
                   schedule_interval: 200,
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
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

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

      Deployer.UpgradeMock
      |> stub(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)
      |> expect(:check, 1, fn %Deployer.Upgrade.Check{
                                from_version: ^from_version,
                                to_version: ^to_version
                              } ->
        {:ok, :full_deployment}
      end)

      with_mock System, [:passthrough],
        cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
        assert {:ok, _pid} =
                 Engine.Worker.start_link(%Engine.Worker{
                   timeout_rollback: 1_000,
                   schedule_interval: 100,
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
      |> expect(:start_service, 1, fn _service ->
        {:ok, self()}
      end)
      |> expect(:stop_service, fn _name, _sname ->
        send(pid, {:handle_ref_event, ref})
        :ok
      end)
      |> expect(:run_pre_commands, 0, fn _sname, _release, _type -> {:ok, []} end)

      Deployer.ReleaseMock
      |> stub(:download_version_map, fn _app_name ->
        %{version: version_to_ghost, hash: "local", pre_commands: []}
      end)
      |> stub(:download_release, fn _app_name, ^version_to_ghost, _download_path ->
        :ok
      end)

      Deployer.UpgradeMock
      |> expect(:prepare_new_path, fn _name, _language, _to_version, _new_path -> :ok end)

      assert capture_log(fn ->
               with_mock System, [:passthrough],
                 cmd: fn "tar", ["-x", "-f", _source_path, "-C", _dest_path] -> {"", 0} end do
                 assert {:ok, _pid} =
                          Engine.Worker.start_link(%Engine.Worker{
                            timeout_rollback: 50,
                            schedule_interval: 200,
                            name: name,
                            language: language
                          })

                 assert_receive {:handle_ref_event, ^ref}, 1_000

                 module_name = String.to_atom(name)
                 state = :sys.get_state(module_name)
                 assert Enum.any?(state.ghosted_version_list, &(&1.version == version_to_ghost))
                 assert state.current == 1
               end
             end) =~ "port: 1 is not stable, ghosting version"
    end
  end
end
