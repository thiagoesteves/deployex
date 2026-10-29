defmodule Foundation.Notifications.RecentTest do
  use ExUnit.Case, async: false

  alias Foundation.Notifications
  alias Foundation.Notifications.Recent
  alias Foundation.Notifications.Recent.Server

  setup do
    name = :"recent_test_#{System.unique_integer([:positive])}"
    start_supervised!({Server, name: name, limit: 3})
    %{name: name}
  end

  test "keeps each event this host sends, newest first", %{name: name} do
    Notifications.notify("crash_restart", %{sname: "myapp-abc123", crash_restart_count: 1})
    Notifications.notify("version_ghosted", %{sname: "myapp-abc123", version: "1.0.1"})

    assert eventually(fn -> length(Server.list(name)) == 2 end)

    assert [
             %Recent{event: "version_ghosted", payload: %{version: "1.0.1"}, at: %DateTime{}},
             %Recent{event: "crash_restart"}
           ] = Server.list(name)
  end

  test "drops the oldest event above the limit", %{name: name} do
    for count <- 1..5, do: Notifications.notify("crash_restart", %{crash_restart_count: count})

    assert eventually(fn ->
             Enum.map(Server.list(name), & &1.payload.crash_restart_count) == [5, 4, 3]
           end)
  end

  test "broadcasts each new event to subscribers" do
    :ok = Recent.subscribe()
    Notifications.notify("config_changed", %{changes_count: 1})

    assert_receive {:recent_notification,
                    %Recent{event: "config_changed", payload: %{changes_count: 1}}}
  end

  test "ignores other messages", %{name: name} do
    send(Process.whereis(name), :unexpected)
    assert Server.list(name) == []
  end

  test "returns no events when the server does not run" do
    assert Server.list(:no_such_recent_server) == []
  end

  test "list/0 reads the application's server" do
    assert is_list(Recent.list())
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end
end
