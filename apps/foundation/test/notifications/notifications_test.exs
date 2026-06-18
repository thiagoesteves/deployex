defmodule Foundation.NotificationsTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.Notifications
  alias Foundation.Notifications.Webhook
  alias Foundation.Yaml

  @enabled_config %Yaml.Notification{
    adapter: Webhook,
    url: "https://hooks.example.com/deployex",
    enabled: true,
    events: [:crash_restart, :deployment_complete],
    options: %{}
  }

  @disabled_config %{@enabled_config | enabled: false}

  @other_events_config %{@enabled_config | events: [:watchdog_threshold_exceeded]}

  @payload %{node: :deployex@host, sname: "myapp-1", crash_restart_count: 1}

  describe "notify/2" do
    @tag :capture_log
    test "dispatches to enabled adapters subscribed to the event" do
      with_mocks([
        {Application, [:passthrough],
         [get_env: fn :foundation, :notifications, [] -> [@enabled_config] end]},
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify(:crash_restart, @payload)

        # Give the Task.Supervisor a moment to dispatch
        Process.sleep(50)

        assert called(Webhook.notify(:crash_restart, @payload, @enabled_config))
      end
    end

    @tag :capture_log
    test "skips disabled adapters" do
      with_mocks([
        {Application, [:passthrough],
         [get_env: fn :foundation, :notifications, [] -> [@disabled_config] end]},
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify(:crash_restart, @payload)
        Process.sleep(50)

        refute called(Webhook.notify(:_, :_, :_))
      end
    end

    @tag :capture_log
    test "skips adapters not subscribed to the event" do
      with_mocks([
        {Application, [:passthrough],
         [get_env: fn :foundation, :notifications, [] -> [@other_events_config] end]},
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        Notifications.notify(:crash_restart, @payload)
        Process.sleep(50)

        refute called(Webhook.notify(:_, :_, :_))
      end
    end

    @tag :capture_log
    test "does nothing when notifications list is empty" do
      with_mocks([
        {Application, [:passthrough], [get_env: fn :foundation, :notifications, [] -> [] end]},
        {Webhook, [], [notify: fn _event, _payload, _config -> :ok end]}
      ]) do
        assert :ok = Notifications.notify(:crash_restart, @payload)
        Process.sleep(50)

        refute called(Webhook.notify(:_, :_, :_))
      end
    end
  end
end
