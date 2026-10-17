defmodule DeployexWeb.AgentApi.EventsChannelTest do
  use DeployexWeb.AgentApiCase

  alias DeployexWeb.AgentApi.EventsChannel
  alias DeployexWeb.AgentApi.Socket

  test "pushes each event of this node, with the webhook body" do
    {:ok, _reply, _socket} =
      Socket
      |> socket(nil, %{api_token: %{name: "ci", scopes: ["read"]}})
      |> subscribe_and_join(EventsChannel, "events")

    Foundation.Notifications.notify("deployment_started", %{
      node: :myapp@host,
      sname: "myapp-abc",
      version: "1.0.0"
    })

    assert_push "event", %{
      event: "deployment_started",
      timestamp: timestamp,
      payload: %{node: :myapp@host, sname: "myapp-abc", version: "1.0.0"}
    }

    assert {:ok, _datetime, 0} = DateTime.from_iso8601(timestamp)
  end

  test "ignores a message that is not an event" do
    {:ok, _reply, socket} =
      Socket
      |> socket(nil, %{api_token: %{name: "ci", scopes: ["read"]}})
      |> subscribe_and_join(EventsChannel, "events")

    send(socket.channel_pid, :unknown)

    refute_push "event", _event
    assert Process.alive?(socket.channel_pid)
  end

  test "refuses a token without the read scope" do
    assert {:error, %{reason: "forbidden"}} =
             Socket
             |> socket(nil, %{api_token: %{name: "ci", scopes: []}})
             |> subscribe_and_join(EventsChannel, "events")
  end
end
