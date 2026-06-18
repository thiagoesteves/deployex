defmodule Foundation.Notifications.SupervisorTest do
  use ExUnit.Case, async: false

  alias Foundation.Notifications.Supervisor, as: NotifSupervisor
  alias Foundation.Notifications.Worker

  @worker_config %Worker{
    adapter: Foundation.Notifications.Webhook,
    url: "https://hooks.example.com",
    enabled: true,
    events: [:crash_restart],
    options: %{}
  }

  describe "start_notification_worker/1" do
    @tag :capture_log
    test "returns {:ok, pid} and starts a live worker process" do
      {:ok, pid} = NotifSupervisor.start_notification_worker(@worker_config)

      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    @tag :capture_log
    test "each call adds a worker to the supervisor" do
      before = DynamicSupervisor.count_children(NotifSupervisor).workers

      {:ok, pid1} = NotifSupervisor.start_notification_worker(@worker_config)
      {:ok, pid2} = NotifSupervisor.start_notification_worker(@worker_config)

      assert DynamicSupervisor.count_children(NotifSupervisor).workers == before + 2

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end

    @tag :capture_log
    test "disabled worker is still started (it simply skips subscriptions)" do
      config = %Worker{@worker_config | enabled: false}

      {:ok, pid} = NotifSupervisor.start_notification_worker(config)

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end
end
