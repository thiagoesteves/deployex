defmodule Foundation.NotificationsTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.Notifications
  alias Foundation.Notifications.Webhook
  alias Foundation.Notifications.Worker
  alias Foundation.Yaml

  @payload %{node: :deployex@host, sname: "myapp-1", crash_restart_count: 1}

  describe "topic/1" do
    test "returns a binary topic string for an event" do
      assert is_binary(Notifications.topic(:crash_restart))
    end

    test "different events produce different topics" do
      assert Notifications.topic(:crash_restart) != Notifications.topic(:deployment_complete)
    end

    test "topic contains the event name" do
      assert Notifications.topic(:crash_restart) =~ "crash_restart"
    end
  end

  describe "notify/2" do
    test "broadcasts to the per-event topic on Foundation.PubSub" do
      Phoenix.PubSub.subscribe(Foundation.PubSub, Notifications.topic(:crash_restart))

      Notifications.notify(:crash_restart, @payload)

      assert_receive {:crash_restart, received_payload}
      assert received_payload == @payload
    end

    test "does not deliver to a subscriber on a different event topic" do
      Phoenix.PubSub.subscribe(Foundation.PubSub, Notifications.topic(:deployment_complete))

      Notifications.notify(:crash_restart, @payload)

      refute_receive {:crash_restart, _}, 50
    end

    test "returns :ok" do
      assert :ok = Notifications.notify(:crash_restart, @payload)
    end
  end

  describe "Worker integration" do
    @tag :capture_log
    test "worker calls its adapter when a matching event is received" do
      config = %Yaml.Notification{
        adapter: Webhook,
        url: "https://hooks.example.com/deployex",
        enabled: true,
        events: [:crash_restart],
        options: %{}
      }

      {:ok, worker} = Worker.start_link(config)

      with_mocks([
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify(:crash_restart, @payload)

        # allow the worker's handle_info to run
        Process.sleep(50)

        assert called(Webhook.notify(:crash_restart, @payload, config))
      end

      GenServer.stop(worker)
    end

    @tag :capture_log
    test "worker ignores events not in its list" do
      config = %Yaml.Notification{
        adapter: Webhook,
        url: "https://hooks.example.com/deployex",
        enabled: true,
        events: [:watchdog_threshold_exceeded],
        options: %{}
      }

      {:ok, worker} = Worker.start_link(config)

      with_mocks([
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify(:crash_restart, @payload)

        Process.sleep(50)

        refute called(Webhook.notify(:_, :_, :_))
      end

      GenServer.stop(worker)
    end

    @tag :capture_log
    test "disabled worker never calls its adapter" do
      config = %Yaml.Notification{
        adapter: Webhook,
        url: "https://hooks.example.com/deployex",
        enabled: false,
        events: [:crash_restart],
        options: %{}
      }

      {:ok, worker} = Worker.start_link(config)

      with_mocks([
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify(:crash_restart, @payload)

        Process.sleep(50)

        refute called(Webhook.notify(:_, :_, :_))
      end

      GenServer.stop(worker)
    end

    @tag :capture_log
    test "two workers for different channels each receive the same event" do
      config_a = %Yaml.Notification{
        adapter: Webhook,
        url: "https://a.example.com",
        enabled: true,
        events: [:crash_restart],
        options: %{}
      }

      config_b = %Yaml.Notification{
        adapter: Webhook,
        url: "https://b.example.com",
        enabled: true,
        events: [:crash_restart],
        options: %{}
      }

      {:ok, worker_a} = Worker.start_link(config_a)
      {:ok, worker_b} = Worker.start_link(config_b)

      with_mocks([
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify(:crash_restart, @payload)

        Process.sleep(50)

        assert called(Webhook.notify(:crash_restart, @payload, config_a))
        assert called(Webhook.notify(:crash_restart, @payload, config_b))
      end

      GenServer.stop(worker_a)
      GenServer.stop(worker_b)
    end
  end
end
