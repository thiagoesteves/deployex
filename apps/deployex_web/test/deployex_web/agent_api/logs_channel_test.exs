defmodule DeployexWeb.AgentApi.LogsChannelTest do
  use DeployexWeb.AgentApiCase

  import Mox

  alias DeployexWeb.AgentApi.Socket
  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias Sentinel.Logs.Message

  setup [:set_mox_global, :verify_on_exit!]

  setup do
    Deployer.StatusMock
    |> stub(:monitoring, fn -> {:ok, FixtureStatus.list()} end)

    Sentinel.LogsMock
    |> stub(:list_active_snames, fn -> ["deployex", "test_app-abc123"] end)

    :ok
  end

  # Joins through the socket, so the topic is routed as a client's would be
  defp join_topic(topic, scopes \\ ["read"]) do
    Socket
    |> socket(nil, %{api_token: %{name: "ci", scopes: scopes}})
    |> subscribe_and_join(topic)
  end

  test "pushes the new lines of one instance and log type" do
    expect(Sentinel.LogsMock, :subscribe_for_new_logs, fn "test_app-abc123", "stderr" -> :ok end)

    {:ok, _reply, socket} = join_topic("logs:test_app-abc123:stderr")

    {:ok, at, 0} = DateTime.from_iso8601("2026-10-23T12:00:00.123Z")
    message = %Message{timestamp: DateTime.to_unix(at, :millisecond), log: "one\ntwo\n"}
    send(socket.channel_pid, {:logs_new_data, "test_app-abc123", "stderr", message})

    assert_push "logs", %{
      logs: [
        %{timestamp: "2026-10-23T12:00:00.123Z", line: "one"},
        %{timestamp: "2026-10-23T12:00:00.123Z", line: "two"}
      ]
    }
  end

  test "pushes nothing for a chunk with no line" do
    stub(Sentinel.LogsMock, :subscribe_for_new_logs, fn _sname, _type -> :ok end)

    {:ok, _reply, socket} = join_topic("logs:test_app-abc123:stdout")

    message = %Message{timestamp: System.os_time(:millisecond), log: "\n"}
    send(socket.channel_pid, {:logs_new_data, "test_app-abc123", "stdout", message})
    send(socket.channel_pid, :unknown)

    refute_push "logs", _logs
    assert Process.alive?(socket.channel_pid)
  end

  test "refuses a topic that names no stored instance and log type" do
    for topic <- [
          "logs:deployex:stdout",
          "logs:test_app-nope00:stdout",
          "logs:test_app-abc123:stdin",
          "logs:test_app-abc123",
          "logs:test_app-abc123:stdout:extra"
        ] do
      assert {:error, %{reason: "not_found"}} = join_topic(topic)
    end
  end

  test "refuses a join before the first status update" do
    stub(Deployer.StatusMock, :monitoring, fn -> {:ok, []} end)

    assert {:error, %{reason: "unavailable"}} = join_topic("logs:test_app-abc123:stdout")
  end

  test "refuses a token without the read scope" do
    assert {:error, %{reason: "forbidden"}} =
             join_topic("logs:test_app-abc123:stdout", ["operate"])
  end
end
