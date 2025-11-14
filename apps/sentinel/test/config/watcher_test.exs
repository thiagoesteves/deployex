defmodule Sentinel.Config.WatcherTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Foundation.Yaml
  alias Sentinel.Config.Changes
  alias Sentinel.Config.Upgradable
  alias Sentinel.Config.Watcher

  @default_upgradable %Upgradable{
    logs_retention_time_ms: 86_400_000,
    metrics_retention_time_ms: 86_400_000,
    monitoring: [],
    applications: [],
    config_checksum: "current_checksum"
  }

  @default_monitoring_config [
    atom: %Foundation.Yaml.Monitoring{
      enable_restart: true,
      warning_threshold_percent: 75,
      restart_threshold_percent: 90
    },
    process: %Foundation.Yaml.Monitoring{
      enable_restart: true,
      warning_threshold_percent: 75,
      restart_threshold_percent: 90
    },
    port: %Foundation.Yaml.Monitoring{
      enable_restart: true,
      warning_threshold_percent: 75,
      restart_threshold_percent: 90
    }
  ]

  @default_application %Foundation.Yaml.Application{
    name: "my_new_app",
    language: "gleam",
    replicas: 1,
    env: [],
    monitoring: [],
    replica_ports: []
  }

  describe "start_link/1" do
    test "starts the GenServer with default name" do
      with_mock Upgradable, from_app_env: fn -> @default_upgradable end do
        assert {:error, {:already_started, pid}} = Watcher.start_link()
        assert Process.alive?(pid)
      end
    end

    test "starts the GenServer with custom name" do
      with_mock Upgradable, from_app_env: fn -> @default_upgradable end do
        assert {:ok, pid} = Watcher.start_link(name: :custom_watcher)

        assert Process.alive?(pid)
        assert Process.whereis(:custom_watcher) == pid
        assert Process.alive?(pid)
      end
    end

    test "starts with custom check interval" do
      with_mock Upgradable, from_app_env: fn -> @default_upgradable end do
        assert {:ok, pid} =
                 Watcher.start_link(check_interval_ms: 10_000, name: :custom_watcher)

        assert Process.alive?(pid)
      end
    end
  end

  describe "init/1" do
    test "initializes with configuration from config loader" do
      with_mock Upgradable, from_app_env: fn -> @default_upgradable end do
        assert {:ok, _pid} = Watcher.start_link(name: :custom_watcher)

        state = :sys.get_state(:custom_watcher)

        assert state.current_config == @default_upgradable
        assert state.pending_config == nil
        assert state.check_interval_ms == 30_000
      end
    end

    test "schedules first config check" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [], [from_app_env: fn -> @default_upgradable end]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:error, :unchanged}
           end
         ]}
      ]) do
        {:ok, _pid} =
          Watcher.start_link(name: :test_schedule, check_interval_ms: 10)

        assert_receive {:handle_ref_event, ^ref}, 1_000

        # If this doesn't crash, the check was scheduled successfully
        assert true
      end
    end
  end

  describe "get_pending_changes/1" do
    test "returns error when no pending changes" do
      with_mock Upgradable, from_app_env: fn -> @default_upgradable end do
        {:ok, pid} = Watcher.start_link(name: :test_no_pending)

        assert {:error, :no_pending_changes} = Watcher.get_pending_changes(pid)
      end
    end

    test "returns pending config when changes exist" do
      with_mock Upgradable, from_app_env: fn -> @default_upgradable end do
        {:ok, pid} = Watcher.start_link(name: :test_with_pending)

        new_config = %Upgradable{
          logs_retention_time_ms: 86_400_000,
          monitoring: [],
          applications: [],
          config_checksum: "new_checksum"
        }

        :sys.replace_state(pid, fn state ->
          %{state | pending_config: new_config, pending_changes: %Changes{}}
        end)

        assert {:ok, %Changes{}} = Watcher.get_pending_changes(pid)
      end
    end
  end

  describe "apply_changes/1" do
    test "returns error when no pending changes" do
      with_mock Upgradable, from_app_env: fn -> @default_upgradable end do
        {:ok, pid} = Watcher.start_link(name: :test_apply_no_pending)

        assert {:error, :no_pending_changes} = Watcher.apply_changes(pid)
      end
    end

    test "applies pending changes successfully (Empty changes)" do
      with_mock Upgradable, from_app_env: fn -> @default_upgradable end do
        {:ok, pid} = Watcher.start_link(name: :test_apply_success)

        new_config = %Upgradable{
          logs_retention_time_ms: 86_400_000,
          monitoring: [],
          applications: [],
          config_checksum: "new_checksum"
        }

        # Set pending config
        :sys.replace_state(pid, fn state ->
          %{state | pending_config: new_config, pending_changes: %Changes{}}
        end)

        assert :ok = Watcher.apply_changes(pid)

        state = :sys.get_state(:test_apply_success)

        # Verify state after applying
        assert state.current_config == new_config
        assert state.pending_config == nil
      end
    end

    test "broadcasts config change when detected" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             # Force new config
             Map.merge(@default_upgradable, %{
               config_checksum: "new_checksum",
               logs_retention_time_ms: 45_000
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        Watcher.subscribe_new_config()
        node = Node.self()

        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_new_config, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            # Verify broadcast received
            assert_receive {:watcher_config_new, ^node, _pending_changes}, 1000
          end)

        assert log =~ "Detected 1 change(s) in upgradable fields: [:logs_retention_time_ms]"
      end
    end

    test "broadcasts config change when applying" do
      with_mock Upgradable, from_app_env: fn -> @default_upgradable end do
        {:ok, pid} = Watcher.start_link(name: :test_apply_broadcast)
        node = Node.self()

        new_config = %Upgradable{
          logs_retention_time_ms: 86_400_000,
          monitoring: [],
          applications: [],
          config_checksum: "new_checksum"
        }

        pending_changes = %Changes{}

        # Subscribe to config changes
        Watcher.subscribe_apply_new_config()

        # Set pending config
        :sys.replace_state(pid, fn state ->
          %{state | pending_config: new_config, pending_changes: pending_changes}
        end)

        assert :ok = Watcher.apply_changes(pid)

        # Verify broadcast received
        assert_receive {:watcher_config_apply, ^node, ^pending_changes}, 1000
      end
    end
  end

  describe "subscribe/0" do
    test "subscribes to new config change notifications" do
      assert :ok = Watcher.subscribe_new_config()
      node = Node.self()

      # Manually broadcast a message
      Phoenix.PubSub.broadcast(
        Foundation.PubSub,
        "deployex::config::changes::new",
        {:watcher_config_new, node, %{test: :data}}
      )

      assert_receive {:watcher_config_new, ^node, %{test: :data}}, 1000
    end

    test "subscribes to apply new config change notifications" do
      assert :ok = Watcher.subscribe_apply_new_config()
      node = Node.self()

      # Manually broadcast a message
      Phoenix.PubSub.broadcast(
        Foundation.PubSub,
        "deployex::config::changes::apply",
        {:watcher_config_apply, node, %{test: :data}}
      )

      assert_receive {:watcher_config_apply, ^node, %{test: :data}}, 1000
    end
  end

  describe "handle_info(:check_config)" do
    test "reschedules check after handling - no changes" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [], [from_app_env: fn -> @default_upgradable end]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:error, :unchanged}
           end
         ]}
      ]) do
        {:ok, pid} =
          Watcher.start_link(name: :test_reschedule, check_interval_ms: 10)

        # Wait for initial check
        assert_receive {:handle_ref_event, ^ref}, 1_000

        # Verify process is still alive and checking
        assert Process.alive?(pid)
      end
    end

    test "detects yaml file not found" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [], [from_app_env: fn -> @default_upgradable end]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:error, :not_found}
           end
         ]}
      ]) do
        {:ok, _pid} = Watcher.start_link(name: :test_not_found, check_interval_ms: 10)

        assert_receive {:handle_ref_event, ^ref}, 1_000

        state = :sys.get_state(:test_not_found)
        assert state.pending_config == nil
      end
    end

    test "handles yaml load error" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config -> @default_upgradable end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:error, :invalid_yaml}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :invalid_yaml, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:invalid_yaml)
            assert state.pending_config == nil
          end)

        assert log =~ "Failed to load YAML configuration"
      end
    end

    test "detects changes in upgradable fields" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               config_checksum: "new_checksum",
               metrics_retention_time_ms: 45_000
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 100)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)
            assert state.pending_config != nil
            assert state.pending_config.metrics_retention_time_ms == 45_000
          end)

        assert log =~ "Detected 1 change(s) in upgradable fields: [:metrics_retention_time_ms]"
      end
    end

    test "detects changes in the YAML file before apply" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             # First 2 calls are the starting process and update,
             # the next ones should be the new version
             called = Process.get("from_yaml", 0)
             Process.put("from_yaml", called + 1)

             if called > 0 do
               send(test_pid, {:handle_ref_event, ref})

               Map.merge(@default_upgradable, %{
                 config_checksum: "new_checksum_2",
                 metrics_retention_time_ms: 90_000
               })
             else
               Map.merge(@default_upgradable, %{
                 config_checksum: "new_checksum_1",
                 metrics_retention_time_ms: 45_000
               })
             end
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)
            assert state.pending_config != nil
            assert state.pending_config.metrics_retention_time_ms == 90_000
          end)

        assert log =~ "Detected 1 change(s) in upgradable fields: [:metrics_retention_time_ms]"
      end
    end

    test "updates checksum when no upgradable changes detected" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             # Same config, just different checksum (non-upgradable field changed)
             Map.merge(@default_upgradable, %{config_checksum: "new_checksum"})
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        {:ok, _pid} = Watcher.start_link(name: :test_no_upgradable_changes, check_interval_ms: 10)

        assert_receive {:handle_ref_event, ^ref}, 1_000

        state = :sys.get_state(:test_no_upgradable_changes)
        assert state.pending_config == nil
        assert state.current_config.config_checksum == "new_checksum"
      end
    end
  end

  describe "timeout changes detection" do
    test "detects logs_retention_time_ms change" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               config_checksum: "new_checksum",
               logs_retention_time_ms: 90_400_000
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config != nil
            assert state.pending_config.logs_retention_time_ms == 90_400_000
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.summary.logs_retention_time_ms.old == 86_400_000
        assert changes.summary.logs_retention_time_ms.new == 90_400_000

        assert log =~ "Detected 1 change(s) in upgradable fields: [:logs_retention_time_ms]"
      end
    end

    test "detects metrics_retention_time_ms change" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               config_checksum: "new_checksum",
               metrics_retention_time_ms: 90_400_000
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config != nil
            assert state.pending_config.metrics_retention_time_ms == 90_400_000
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.summary.metrics_retention_time_ms.old == 86_400_000
        assert changes.summary.metrics_retention_time_ms.new == 90_400_000

        assert log =~ "Detected 1 change(s) in upgradable fields: [:metrics_retention_time_ms]"
      end
    end

    test "detects multiple timeout changes" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               config_checksum: "new_checksum",
               logs_retention_time_ms: 90_400_000,
               metrics_retention_time_ms: 90_000
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config != nil
            assert state.pending_config.logs_retention_time_ms == 90_400_000
            assert state.pending_config.metrics_retention_time_ms == 90_000
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.changes_count == 2
        assert Map.has_key?(changes.summary, :logs_retention_time_ms)
        assert Map.has_key?(changes.summary, :metrics_retention_time_ms)

        assert log =~
                 "Detected 2 change(s) in upgradable fields: [:logs_retention_time_ms, :metrics_retention_time_ms]"
      end
    end
  end

  describe "monitoring changes detection" do
    test "detects added monitoring configuration" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               monitoring: @default_monitoring_config
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.monitoring != []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.changes_count == 1
        assert changes.summary.monitoring.old == []
        assert changes.summary.monitoring.new == @default_monitoring_config

        assert log =~ "Detected 1 change(s) in upgradable fields: [:monitoring]"
      end
    end

    test "detects removed monitoring configuration" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               monitoring: @default_monitoring_config
             })
           end,
           from_yaml: fn _config -> @default_upgradable end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.monitoring == []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.changes_count == 1
        assert changes.summary.monitoring.old == @default_monitoring_config
        assert changes.summary.monitoring.new == []

        assert log =~ "Detected 1 change(s) in upgradable fields: [:monitoring]"
      end
    end

    test "detects modified monitoring configuration" do
      test_pid = self()
      ref = make_ref()

      new_monitoring = [
        process: %Foundation.Yaml.Monitoring{
          enable_restart: false,
          warning_threshold_percent: 75,
          restart_threshold_percent: 90
        }
      ]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               monitoring: @default_monitoring_config
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               monitoring: new_monitoring
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.monitoring != []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.changes_count == 1
        assert changes.summary.monitoring.old == @default_monitoring_config
        assert changes.summary.monitoring.new == new_monitoring

        assert log =~ "Detected 1 change(s) in upgradable fields: [:monitoring]"
      end
    end

    test "no changes when monitoring is identical" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               monitoring: @default_monitoring_config
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               monitoring: @default_monitoring_config
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

        assert_receive {:handle_ref_event, ^ref}, 1_000

        state = :sys.get_state(:test_changes)

        assert state.pending_config == nil

        {:error, :no_pending_changes} = Watcher.get_pending_changes(:test_changes)
      end
    end
  end

  describe "application changes detection" do
    test "detects added application" do
      test_pid = self()
      ref = make_ref()

      new_applications = [@default_application]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               applications: new_applications
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.applications != []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.changes_count == 1
        assert changes.summary.applications.old == []
        assert Enum.map(changes.summary.applications.new, & &1.name) == ["my_new_app"]

        assert log =~ "Detected 1 change(s) in upgradable fields: [:applications]"
      end
    end

    test "detects removed application" do
      test_pid = self()
      ref = make_ref()

      new_applications = [@default_application]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: new_applications
             })
           end,
           from_yaml: fn _config -> @default_upgradable end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.applications == []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.changes_count == 1
        assert Enum.map(changes.summary.applications.old, & &1.name) == ["my_new_app"]
        assert changes.summary.applications.new == []

        assert log =~ "Detected 1 change(s) in upgradable fields: [:applications]"
      end
    end

    test "No changes in the application" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: [@default_application]
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               config_checksum: "new_checksum",
               applications: [@default_application]
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

        assert_receive {:handle_ref_event, ^ref}, 1_000

        state = :sys.get_state(:test_changes)

        assert state.pending_config == nil

        {:error, :no_pending_changes} = Watcher.get_pending_changes(:test_changes)
      end
    end

    test "detects modified application language" do
      test_pid = self()
      ref = make_ref()

      old_applications = [Map.merge(@default_application, %{language: "gleam"})]
      new_applications = [Map.merge(@default_application, %{language: "elixir"})]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: old_applications
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               applications: new_applications
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.applications != []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.summary.applications.details["my_new_app"].status == :modified
        assert changes.summary.applications.details["my_new_app"].changes.language.old == "gleam"
        assert changes.summary.applications.details["my_new_app"].changes.language.new == "elixir"

        assert log =~ "Detected 1 change(s) in upgradable fields: [:applications]"
      end
    end

    test "detects modified application replicas" do
      test_pid = self()
      ref = make_ref()

      old_applications = [Map.merge(@default_application, %{replicas: 1})]
      new_applications = [Map.merge(@default_application, %{replicas: 5})]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: old_applications
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               applications: new_applications
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.applications != []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.summary.applications.details["my_new_app"].status == :modified
        assert changes.summary.applications.details["my_new_app"].changes.replicas.old == 1
        assert changes.summary.applications.details["my_new_app"].changes.replicas.new == 5

        assert log =~ "Detected 1 change(s) in upgradable fields: [:applications]"
      end
    end

    test "detects modified application deploy_rollback_timeout_ms" do
      test_pid = self()
      ref = make_ref()

      old_applications = [Map.merge(@default_application, %{deploy_rollback_timeout_ms: 60_000})]
      new_applications = [Map.merge(@default_application, %{deploy_rollback_timeout_ms: 80_000})]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: old_applications
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               applications: new_applications
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.applications != []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.summary.applications.details["my_new_app"].status == :modified

        assert changes.summary.applications.details["my_new_app"].changes.deploy_rollback_timeout_ms.old ==
                 60_000

        assert changes.summary.applications.details["my_new_app"].changes.deploy_rollback_timeout_ms.new ==
                 80_000

        assert log =~ "Detected 1 change(s) in upgradable fields: [:applications]"
      end
    end

    test "detects modified application deploy_schedule_interval_ms" do
      test_pid = self()
      ref = make_ref()

      old_applications = [Map.merge(@default_application, %{deploy_schedule_interval_ms: 60_000})]
      new_applications = [Map.merge(@default_application, %{deploy_schedule_interval_ms: 80_000})]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: old_applications
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               applications: new_applications
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.applications != []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.summary.applications.details["my_new_app"].status == :modified

        assert changes.summary.applications.details["my_new_app"].changes.deploy_schedule_interval_ms.old ==
                 60_000

        assert changes.summary.applications.details["my_new_app"].changes.deploy_schedule_interval_ms.new ==
                 80_000

        assert log =~ "Detected 1 change(s) in upgradable fields: [:applications]"
      end
    end

    test "detects modified application environment variables" do
      test_pid = self()
      ref = make_ref()

      old_applications = [Map.merge(@default_application, %{env: ["SECRET=400"]})]
      new_applications = [Map.merge(@default_application, %{env: ["SECRET=500"]})]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: old_applications
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               applications: new_applications
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.applications != []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.summary.applications.details["my_new_app"].status == :modified

        assert changes.summary.applications.details["my_new_app"].changes.env.old == [
                 "SECRET=400"
               ]

        assert changes.summary.applications.details["my_new_app"].changes.env.new == [
                 "SECRET=500"
               ]

        assert log =~ "Detected 1 change(s) in upgradable fields: [:applications]"
      end
    end

    test "detects modified replica ports" do
      test_pid = self()
      ref = make_ref()

      old_applications = [
        Map.merge(@default_application, %{replica_ports: [%{key: "PORT", base: 5000}]})
      ]

      new_applications = [
        Map.merge(@default_application, %{replica_ports: [%{key: "PORT", base: 6000}]})
      ]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: old_applications
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               applications: new_applications
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config.applications != []
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.summary.applications.details["my_new_app"].status == :modified

        assert changes.summary.applications.details["my_new_app"].changes.replica_ports.old == [
                 %{key: "PORT", base: 5000}
               ]

        assert changes.summary.applications.details["my_new_app"].changes.replica_ports.new == [
                 %{key: "PORT", base: 6000}
               ]

        assert log =~ "Detected 1 change(s) in upgradable fields: [:applications]"
      end
    end

    test "no changes when application is identical" do
      test_pid = self()
      ref = make_ref()

      old_applications = [@default_application]
      new_applications = [@default_application]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: old_applications
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               applications: new_applications
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

        assert_receive {:handle_ref_event, ^ref}, 1_000

        state = :sys.get_state(:test_changes)

        assert state.pending_config == nil

        {:error, :no_pending_changes} = Watcher.get_pending_changes(:test_changes)
      end
    end
  end

  describe "complex scenarios" do
    test "detects multiple changes across different configuration areas" do
      test_pid = self()
      ref = make_ref()

      old_applications = [
        Map.merge(@default_application, %{replica_ports: [%{key: "PORT", base: 5000}]})
      ]

      new_applications = [
        Map.merge(@default_application, %{replica_ports: [%{key: "PORT", base: 6000}]})
      ]

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn ->
             Map.merge(@default_upgradable, %{
               applications: old_applications
             })
           end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               config_checksum: "new_checksum",
               logs_retention_time_ms: 90_400_000,
               metrics_retention_time_ms: 90_000,
               applications: new_applications
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        log =
          capture_log(fn ->
            {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

            assert_receive {:handle_ref_event, ^ref}, 1_000

            state = :sys.get_state(:test_changes)

            assert state.pending_config != nil
            assert state.pending_config.logs_retention_time_ms == 90_400_000
            assert state.pending_config.metrics_retention_time_ms == 90_000
          end)

        {:ok, changes} = Watcher.get_pending_changes(:test_changes)

        assert changes.changes_count == 3
        assert Map.has_key?(changes.summary, :logs_retention_time_ms)
        assert Map.has_key?(changes.summary, :metrics_retention_time_ms)
        assert Map.has_key?(changes.summary, :applications)

        assert log =~
                 "Detected 3 change(s) in upgradable fields: [:applications, :logs_retention_time_ms, :metrics_retention_time_ms]"
      end
    end

    test "Ignore new timeouts values with nil values" do
      test_pid = self()
      ref = make_ref()

      with_mocks([
        {Upgradable, [],
         [
           from_app_env: fn -> @default_upgradable end,
           from_yaml: fn _config ->
             Map.merge(@default_upgradable, %{
               config_checksum: "new_checksum",
               logs_retention_time_ms: nil,
               deploy_schedule_interval_ms: nil,
               deploy_rollback_timeout_ms: nil
             })
           end
         ]},
        {Yaml, [],
         [
           load: fn %Yaml{config_checksum: "current_checksum"} ->
             send(test_pid, {:handle_ref_event, ref})
             {:ok, %Yaml{}}
           end
         ]}
      ]) do
        {:ok, _pid} = Watcher.start_link(name: :test_changes, check_interval_ms: 10)

        assert_receive {:handle_ref_event, ^ref}, 1_000

        state = :sys.get_state(:test_changes)

        assert state.pending_config == nil

        {:error, :no_pending_changes} = Watcher.get_pending_changes(:test_changes)
      end
    end
  end

  test "Test non-mocked lod_config" do
    assert %Upgradable{} == Upgradable.from_yaml(%Yaml{})
  end

  test "Improve coverage" do
    assert {:error, :no_pending_changes} == Watcher.get_pending_changes()
    assert {:error, :no_pending_changes} == Watcher.apply_changes()
  end
end
