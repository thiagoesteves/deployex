defmodule Deployer.SelfUpgrade.WorkerTest do
  use ExUnit.Case, async: true
  import Mox

  alias Deployer.SelfUpgrade.Worker

  setup :verify_on_exit!

  defp running, do: Application.spec(:foundation, :vsn) |> to_string()

  defp start do
    pid = start_supervised!({Worker, name: nil, interval_ms: :never})
    allow(Deployer.SelfUpgrade.SourceMock, self(), pid)
    allow(Deployer.SelfUpgrade.ExecutorMock, self(), pid)
    pid
  end

  test "no drift is a no-op" do
    pid = start()
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, fn -> {:ok, running()} end)
    assert :noop = Worker.reconcile(pid)
  end

  test "drift triggers a hot upgrade" do
    pid = start()
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, fn -> {:ok, "99.0.0"} end)
    expect(Deployer.SelfUpgrade.ExecutorMock, :hot_upgrade, fn "99.0.0" -> :ok end)
    assert :ok = Worker.reconcile(pid)
  end

  test "a failed hot upgrade stays on the current version and does not retry it" do
    pid = start()
    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, 2, fn -> {:ok, "99.0.0"} end)
    expect(Deployer.SelfUpgrade.ExecutorMock, :hot_upgrade, 1, fn "99.0.0" -> {:error, :nope} end)
    assert {:error, _} = Worker.reconcile(pid)
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
    pid = start_supervised!({Worker, name: nil, interval_ms: 60_000})
    allow(Deployer.SelfUpgrade.SourceMock, self(), pid)
    allow(Deployer.SelfUpgrade.ExecutorMock, self(), pid)
    Phoenix.PubSub.subscribe(Deployer.PubSub, "self_upgrade")

    expect(Deployer.SelfUpgrade.SourceMock, :desired_version, fn -> {:ok, "99.0.0"} end)
    expect(Deployer.SelfUpgrade.ExecutorMock, :hot_upgrade, fn "99.0.0" -> :ok end)

    send(pid, :tick)

    assert_receive {:self_upgrade, :hot_ok, %{version: "99.0.0"}}
  end
end
