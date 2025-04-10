defmodule Deployex.Logs.ServerTest do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  alias Deployex.Fixture.Nodes, as: FixtureNodes
  alias Deployex.Logs.Message
  alias Deployex.Logs.Server
  alias Deployex.Terminal

  setup [
    :set_mox_from_context,
    :verify_on_exit!,
    :create_consumer
  ]

  test "[un]subscribe_for_new_logs/0", %{node: node, pid: pid} do
    log_type = "new-log-type"
    message = "[info] simple log"
    Server.subscribe_for_new_logs(node, log_type)

    send(
      pid,
      {:terminal_update,
       %{
         metadata: %{context: :terminal_logs, node: node, type: log_type},
         myself: self(),
         message: message
       }}
    )

    assert_receive {:logs_new_data, ^node, ^log_type, %Message{timestamp: _, log: ^message}},
                   1_000

    # Validate by inspection
    Server.unsubscribe_for_new_logs(node, log_type)
  end

  test "get_types_by_node/1 valid node", %{node: node, pid: pid} do
    log_type = "new-log-type"
    message = "[info] simple log"
    Server.subscribe_for_new_logs(node, log_type)

    send(
      pid,
      {:terminal_update,
       %{
         metadata: %{context: :terminal_logs, node: node, type: log_type},
         myself: self(),
         message: message
       }}
    )

    assert_receive {:logs_new_data, ^node, ^log_type, %Message{timestamp: _, log: _message}},
                   1_000

    log_types = Server.get_types_by_node(node)
    assert log_type in log_types
  end

  test "node/1 invalid node" do
    assert [] == Server.get_types_by_node(nil)
  end

  test "list_active_nodes/0", %{node: node} do
    nodes = Server.list_active_nodes()
    assert node in nodes
  end

  test "list_data_by_node_key/3", %{node: node, pid: pid} do
    log_type = "new-log-type"
    Server.subscribe_for_new_logs(node, log_type)

    Enum.each(1..5, fn index ->
      send(
        pid,
        {:terminal_update,
         %{
           metadata: %{context: :terminal_logs, node: node, type: log_type},
           myself: self(),
           message: "[info] log #{index}"
         }}
      )
    end)

    assert_receive {:logs_new_data, ^node, ^log_type,
                    %Message{timestamp: _, log: "[info] log 5"}},
                   1_000

    assert [
             %Message{timestamp: _, log: "[info] log 1"},
             %Message{timestamp: _, log: "[info] log 2"},
             %Message{timestamp: _, log: "[info] log 3"},
             %Message{timestamp: _, log: "[info] log 4"},
             %Message{timestamp: _, log: "[info] log 5"}
           ] = Server.list_data_by_node_log_type(node |> to_string(), log_type, order: :asc)

    assert [
             %Message{timestamp: _, log: "[info] log 5"},
             %Message{timestamp: _, log: "[info] log 4"},
             %Message{timestamp: _, log: "[info] log 3"},
             %Message{timestamp: _, log: "[info] log 2"},
             %Message{timestamp: _, log: "[info] log 1"}
           ] = Server.list_data_by_node_log_type(node |> to_string(), log_type, order: :desc)

    assert [
             %Message{timestamp: _, log: "[info] log 1"},
             %Message{timestamp: _, log: "[info] log 2"},
             %Message{timestamp: _, log: "[info] log 3"},
             %Message{timestamp: _, log: "[info] log 4"},
             %Message{timestamp: _, log: "[info] log 5"}
           ] = Server.list_data_by_node_log_type(node |> to_string(), log_type)
  end

  test "Pruning expiring entries", %{node: node, pid: pid} do
    log_type = "new-log-type"
    Server.subscribe_for_new_logs(node, log_type)

    now = System.os_time(:millisecond)

    with_mock System, os_time: fn _ -> now - 120_000 end do
      Enum.each(1..5, fn index ->
        send(
          pid,
          {:terminal_update,
           %{
             metadata: %{context: :terminal_logs, node: node, type: log_type},
             myself: self(),
             message: "[info] log #{index}"
           }}
        )
      end)

      assert_receive {:logs_new_data, ^node, ^log_type,
                      %Message{timestamp: _, log: "[info] log 5"}},
                     1_000
    end

    assert [
             %Message{timestamp: _, log: "[info] log 1"},
             %Message{timestamp: _, log: "[info] log 2"},
             %Message{timestamp: _, log: "[info] log 3"},
             %Message{timestamp: _, log: "[info] log 4"},
             %Message{timestamp: _, log: "[info] log 5"}
           ] = Server.list_data_by_node_log_type(node |> to_string(), log_type)

    send(pid, :prune_expired_entries)
    :timer.sleep(100)

    assert [] = Server.list_data_by_node_log_type(node |> to_string(), log_type, order: :asc)
  end

  test "Check Node up with expected node", %{node: node, pid: pid} do
    log_type = "new-log-type"
    message = "message"
    Server.subscribe_for_new_logs(node, log_type)

    send(pid, {:nodeup, node})

    send(
      pid,
      {:terminal_update,
       %{
         metadata: %{context: :terminal_logs, node: node, type: log_type},
         myself: self(),
         message: message
       }}
    )

    assert_receive {:logs_new_data, ^node, ^log_type, %Message{timestamp: _, log: ^message}},
                   1_000
  end

  test "Check Node down with expected node", %{node: node, pid: pid} do
    log_type = "stderr"
    message = "DeployEx detected node down for node: #{node}"
    Server.subscribe_for_new_logs(node, log_type)

    send(pid, {:nodedown, node})

    assert_receive {:logs_new_data, ^node, ^log_type, %Message{timestamp: _, log: ^message}},
                   1_000
  end

  test "Check Node down with unexpected node", %{pid: pid} do
    log_type = "stderr"
    node = :"non-valid-node@nohost"
    message = "DeployEx detected node down for node: #{node}"
    Server.subscribe_for_new_logs(node, log_type)

    send(pid, {:nodedown, :"non-valid-node@nohost"})

    refute_receive {:logs_new_data, ^node, _log_type, %Message{timestamp: _, log: ^message}},
                   1_000
  end

  defp create_consumer(context) do
    Deployex.OpSysMock
    |> stub(:run, fn _command, _options -> {:ok, self(), "123456"} end)
    |> stub(:stop, fn _pid -> :ok end)

    test_pid = self()

    with_mock Terminal, new: fn %Terminal{} -> :ok end do
      {:ok, pid} = Server.start_link(data_retention_period: :timer.minutes(1))
      send(test_pid, {:server_pid, pid})
    end

    assert_receive {:server_pid, pid}, 1_000

    node = FixtureNodes.test_node(1)

    context
    |> Map.put(:node, String.to_atom(node))
    |> Map.put(:pid, pid)
  end
end
