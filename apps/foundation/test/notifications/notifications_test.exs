defmodule Foundation.NotificationsTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.Notifications
  alias Foundation.Notifications.Supervisor, as: NotifSupervisor
  alias Foundation.Notifications.Webhook
  alias Foundation.Notifications.Worker

  @payload %{node: :deployex@host, sname: "myapp-1", crash_restart_count: 1}

  describe "start_notification_manager/1" do
    @tag :capture_log
    test "starts one worker per Foundation.Yaml.Notification entry" do
      configs = [
        %Foundation.Yaml.Notification{
          adapter: Webhook,
          url: "https://a.example.com",
          enabled: true,
          events: ["crash_restart"],
          options: %Foundation.Yaml.Notification.Options{}
        },
        %Foundation.Yaml.Notification{
          adapter: Webhook,
          url: "https://b.example.com",
          enabled: true,
          events: ["deployment_complete"],
          options: %Foundation.Yaml.Notification.Options{}
        }
      ]

      before = DynamicSupervisor.count_children(NotifSupervisor).workers
      assert :ok = Notifications.start_notification_manager(configs)
      assert DynamicSupervisor.count_children(NotifSupervisor).workers == before + 2

      Notifications.stop_notification_manager()
    end

    @tag :capture_log
    test "converts nested Options struct to plain map in Worker" do
      configs = [
        %Foundation.Yaml.Notification{
          adapter: Webhook,
          url: "https://options.example.com",
          enabled: true,
          events: ["crash_restart"],
          options: %Foundation.Yaml.Notification.Options{
            username: "DeployEx-Bot",
            icon_emoji: ":rocket:"
          }
        }
      ]

      before = DynamicSupervisor.count_children(NotifSupervisor).workers
      assert :ok = Notifications.start_notification_manager(configs)
      assert DynamicSupervisor.count_children(NotifSupervisor).workers == before + 1

      [worker_pid | _] =
        NotifSupervisor
        |> DynamicSupervisor.which_children()
        |> Enum.map(fn {_, pid, _, _} -> pid end)

      %Worker{options: options} = :sys.get_state(worker_pid)
      assert is_map(options) and not is_struct(options)
      assert options.username == "DeployEx-Bot"
      assert options.icon_emoji == ":rocket:"

      Notifications.stop_notification_manager()
    end

    @tag :capture_log
    test "accepts plain map configs (non-struct)" do
      configs = [
        %{
          adapter: Webhook,
          url: "https://map.example.com",
          enabled: true,
          events: ["crash_restart"],
          options: %{}
        }
      ]

      before = DynamicSupervisor.count_children(NotifSupervisor).workers
      assert :ok = Notifications.start_notification_manager(configs)
      assert DynamicSupervisor.count_children(NotifSupervisor).workers == before + 1

      Notifications.stop_notification_manager()
    end
  end

  describe "stop_notification_manager/0" do
    @tag :capture_log
    test "terminates all running notification workers" do
      config = %Foundation.Yaml.Notification{
        adapter: Webhook,
        url: "https://stop-test.example.com",
        enabled: true,
        events: ["crash_restart"],
        options: %Foundation.Yaml.Notification.Options{}
      }

      Notifications.start_notification_manager([config, config])
      assert DynamicSupervisor.count_children(NotifSupervisor).workers >= 2

      assert :ok = Notifications.stop_notification_manager()
      assert DynamicSupervisor.count_children(NotifSupervisor).workers == 0
    end
  end

  describe "topic/1" do
    test "returns a binary topic string for an event" do
      assert is_binary(Notifications.topic("crash_restart"))
    end

    test "different events produce different topics" do
      assert Notifications.topic("crash_restart") != Notifications.topic("deployment_complete")
    end

    test "topic contains the event name" do
      assert Notifications.topic("crash_restart") =~ "crash_restart"
    end
  end

  describe "notify/2" do
    test "broadcasts to the per-event topic on Foundation.PubSub" do
      Phoenix.PubSub.subscribe(Foundation.PubSub, Notifications.topic("crash_restart"))

      Notifications.notify("crash_restart", @payload)

      assert_receive {"crash_restart", received_payload}
      assert received_payload == @payload
    end

    test "does not deliver to a subscriber on a different event topic" do
      Phoenix.PubSub.subscribe(Foundation.PubSub, Notifications.topic("deployment_complete"))

      Notifications.notify("crash_restart", @payload)

      refute_receive {"crash_restart", _}, 50
    end

    test "returns :ok" do
      assert :ok = Notifications.notify("crash_restart", @payload)
    end
  end

  describe "Worker integration" do
    @tag :capture_log
    test "worker calls its adapter when a matching event is received" do
      config = %Worker{
        adapter: Webhook,
        url: "https://hooks.example.com/deployex",
        enabled: true,
        events: ["crash_restart"],
        options: %{}
      }

      {:ok, worker} = Worker.start_link(config)

      with_mocks([
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify("crash_restart", @payload)

        # allow the worker's handle_info to run
        Process.sleep(50)

        assert called(Webhook.notify("crash_restart", @payload, config))
      end

      GenServer.stop(worker)
    end

    @tag :capture_log
    test "worker ignores events not in its list" do
      config = %Worker{
        adapter: Webhook,
        url: "https://hooks.example.com/deployex",
        enabled: true,
        events: ["watchdog_threshold_exceeded"],
        options: %{}
      }

      {:ok, worker} = Worker.start_link(config)

      with_mocks([
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify("crash_restart", @payload)

        Process.sleep(50)

        refute called(Webhook.notify(:_, :_, :_))
      end

      GenServer.stop(worker)
    end

    @tag :capture_log
    test "disabled worker never calls its adapter" do
      config = %Worker{
        adapter: Webhook,
        url: "https://hooks.example.com/deployex",
        enabled: false,
        events: ["crash_restart"],
        options: %{}
      }

      {:ok, worker} = Worker.start_link(config)

      with_mocks([
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify("crash_restart", @payload)

        Process.sleep(50)

        refute called(Webhook.notify(:_, :_, :_))
      end

      GenServer.stop(worker)
    end

    @tag :capture_log
    test "adapter error is logged but worker stays alive" do
      config = %Worker{
        adapter: Webhook,
        url: "https://hooks.example.com/deployex",
        enabled: true,
        events: ["crash_restart"],
        options: %{}
      }

      {:ok, worker} = Worker.start_link(config)

      with_mocks([
        {Webhook, [], [notify: fn _event, _payload, _config -> {:error, :econnrefused} end]}
      ]) do
        Notifications.notify("crash_restart", @payload)

        Process.sleep(50)

        assert called(Webhook.notify("crash_restart", @payload, config))
        assert Process.alive?(worker)
      end

      GenServer.stop(worker)
    end

    @tag :capture_log
    test "two workers for different channels each receive the same event" do
      config_a = %Worker{
        adapter: Webhook,
        url: "https://a.example.com",
        enabled: true,
        events: ["crash_restart"],
        options: %{}
      }

      config_b = %Worker{
        adapter: Webhook,
        url: "https://b.example.com",
        enabled: true,
        events: ["crash_restart"],
        options: %{}
      }

      {:ok, worker_a} = Worker.start_link(config_a)
      {:ok, worker_b} = Worker.start_link(config_b)

      with_mocks([
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify("crash_restart", @payload)

        Process.sleep(50)

        assert called(Webhook.notify("crash_restart", @payload, config_a))
        assert called(Webhook.notify("crash_restart", @payload, config_b))
      end

      GenServer.stop(worker_a)
      GenServer.stop(worker_b)
    end
  end
end
