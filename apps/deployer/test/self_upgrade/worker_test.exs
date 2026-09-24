defmodule Deployer.SelfUpgrade.WorkerTest do
  use ExUnit.Case, async: false
  import Mox

  alias Deployer.SelfUpgrade.Worker

  # The upgrade runs in a Task (a separate process), so the mocks must be callable
  # from any process, not just the test pid.
  setup :set_mox_global
  setup :verify_on_exit!

  defp running, do: Application.spec(:foundation, :vsn) |> to_string()

  defp start(opts \\ [interval_ms: :never]) do
    start_supervised!({Task.Supervisor, name: Deployer.SelfUpgrade.TaskSupervisor})
    start_supervised!({Worker, [name: nil] ++ opts})
  end

  test "no drift is a no-op" do
    pid = start()
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, fn -> {:ok, running()} end)
    assert :noop = Worker.reconcile(pid)
  end

  test "drift starts a hot upgrade and reports success" do
    Phoenix.PubSub.subscribe(Deployer.PubSub, "self_upgrade")
    pid = start()
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, fn -> {:ok, "99.0.0"} end)
    expect(Deployer.SelfUpgrade.ExecutorMock, :hot_upgrade, fn "99.0.0" -> :ok end)

    assert :started = Worker.reconcile(pid)
    assert_receive {:self_upgrade, :hot_ok, %{version: "99.0.0"}}, 1_000
  end

  test "a second reconcile while upgrading is single-flight" do
    test_pid = self()
    pid = start()
    # desired_version is only asked once: the in-flight guard short-circuits the second call.
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, fn -> {:ok, "99.0.0"} end)

    expect(Deployer.SelfUpgrade.ExecutorMock, :hot_upgrade, fn "99.0.0" ->
      send(test_pid, {:upgrade_running, self()})
      receive do: (:release -> :ok)
    end)

    assert :started = Worker.reconcile(pid)
    assert_receive {:upgrade_running, task_pid}, 1_000
    assert :in_progress = Worker.reconcile(pid)
    send(task_pid, :release)
  end

  test "a failed hot upgrade stays on the current version and does not retry it" do
    Phoenix.PubSub.subscribe(Deployer.PubSub, "self_upgrade")
    pid = start()
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, 2, fn -> {:ok, "99.0.0"} end)
    expect(Deployer.SelfUpgrade.ExecutorMock, :hot_upgrade, 1, fn "99.0.0" -> {:error, :nope} end)

    assert :started = Worker.reconcile(pid)
    assert_receive {:self_upgrade, :hot_failed, %{version: "99.0.0"}}, 1_000
    assert :noop = Worker.reconcile(pid)
  end

  test ":none source is a no-op" do
    pid = start()
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, fn -> :none end)
    assert :noop = Worker.reconcile(pid)
  end

  test "source error is a no-op" do
    pid = start()
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, fn -> {:error, :boom} end)
    assert :noop = Worker.reconcile(pid)
  end

  test "tick reconciles and reschedules on a real timer" do
    Phoenix.PubSub.subscribe(Deployer.PubSub, "self_upgrade")
    pid = start(interval_ms: 60_000)
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, fn -> {:ok, "99.0.0"} end)
    expect(Deployer.SelfUpgrade.ExecutorMock, :hot_upgrade, fn "99.0.0" -> :ok end)

    send(pid, :tick)

    assert_receive {:self_upgrade, :hot_ok, %{version: "99.0.0"}}, 1_000
  end
end
