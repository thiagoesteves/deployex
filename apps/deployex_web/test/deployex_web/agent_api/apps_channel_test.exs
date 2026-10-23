defmodule DeployexWeb.AgentApi.AppsChannelTest do
  use DeployexWeb.AgentApiCase

  import Mox

  alias DeployexWeb.AgentApi.AppsChannel
  alias DeployexWeb.AgentApi.Socket
  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [:set_mox_global, :verify_on_exit!]

  setup do
    Deployer.StatusMock
    |> stub(:subscribe, fn -> :ok end)
    |> stub(:subscribe_ghosted_versions, fn _name -> :ok end)
    |> stub(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> stub(:ghosted_version_list, fn _name -> [] end)

    :ok
  end

  defp join do
    Socket
    |> socket(nil, %{api_token: %{name: "ci", scopes: ["read"]}})
    |> subscribe_and_join(AppsChannel, "apps")
  end

  test "replies to the join with a snapshot of each monitored app" do
    assert {:ok, %{apps: [%{name: "test_app", ghosted_versions: [], instances: [_]}]}, _socket} =
             join()
  end

  test "pushes an app only when its snapshot changes" do
    {:ok, _reply, socket} = join()

    send(socket.channel_pid, {:monitoring_app_updated, node(), FixtureStatus.list()})
    refute_push "app", _snapshot

    restarted = FixtureStatus.application(%{crash_restart_count: 1})

    send(
      socket.channel_pid,
      {:monitoring_app_updated, node(), [FixtureStatus.deployex(), restarted]}
    )

    assert_push "app", %{name: "test_app", instances: [%{crash_restart_count: 1}]}
  end

  test "does not push an app when only its display uptime changes" do
    {:ok, _reply, socket} = join()

    later = FixtureStatus.application(%{uptime: "2d ago"})
    send(socket.channel_pid, {:monitoring_app_updated, node(), [FixtureStatus.deployex(), later]})

    refute_push "app", _snapshot
  end

  test "pushes an app when an instance starts again" do
    {:ok, _reply, socket} = join()

    started = FixtureStatus.application(%{started_at: ~U[2026-10-23 12:00:00Z]})

    send(
      socket.channel_pid,
      {:monitoring_app_updated, node(), [FixtureStatus.deployex(), started]}
    )

    assert_push "app", %{name: "test_app", instances: [%{started_at: ~U[2026-10-23 12:00:00Z]}]}
  end

  test "pushes an app when its ghosted list changes" do
    {:ok, _reply, socket} = join()

    send(
      socket.channel_pid,
      {:ghosted_versions_updated, node(), "test_app", [FixtureStatus.version()]}
    )

    assert_push "app", %{name: "test_app", ghosted_versions: ["1.0.0"]}
  end

  test "pushes an app that is added after the join, and follows its ghosted list" do
    stub(Deployer.StatusMock, :monitoring, fn -> {:ok, [FixtureStatus.deployex()]} end)

    assert {:ok, %{apps: []}, socket} = join()

    expect(Deployer.StatusMock, :subscribe_ghosted_versions, fn "test_app" -> :ok end)
    send(socket.channel_pid, {:monitoring_app_updated, node(), FixtureStatus.list()})

    assert_push "app", %{name: "test_app"}
  end

  test "pushes app_removed for an app that the host no longer monitors" do
    {:ok, _reply, socket} = join()

    send(socket.channel_pid, {:monitoring_app_updated, node(), [FixtureStatus.deployex()]})

    assert_push "app_removed", %{name: "test_app"}
    refute_push "app", _snapshot
  end

  test "ignores the updates of other DeployEx nodes" do
    {:ok, _reply, socket} = join()

    restarted = FixtureStatus.application(%{crash_restart_count: 1})

    send(
      socket.channel_pid,
      {:monitoring_app_updated, :other@host, [FixtureStatus.deployex(), restarted]}
    )

    send(
      socket.channel_pid,
      {:ghosted_versions_updated, :other@host, "test_app", [FixtureStatus.version()]}
    )

    refute_push "app", _snapshot
  end

  test "refuses the join when the status server does not answer, or has no list yet" do
    stub(Deployer.StatusMock, :monitoring, fn -> {:error, :rescued} end)
    assert {:error, %{reason: "unavailable"}} = join()

    stub(Deployer.StatusMock, :monitoring, fn -> {:ok, []} end)
    assert {:error, %{reason: "unavailable"}} = join()
  end

  test "refuses a token without the read scope" do
    assert {:error, %{reason: "forbidden"}} =
             Socket
             |> socket(nil, %{api_token: %{name: "ci", scopes: []}})
             |> subscribe_and_join(AppsChannel, "apps")
  end
end
