defmodule Sentinel.LogsTest do
  use ExUnit.Case, async: false

  import Mox
  setup :verify_on_exit!

  alias Sentinel.Logs

  test "subscribe_for_new_logs/2" do
    Sentinel.LogsMock
    |> expect(:subscribe_for_new_logs, fn _node, _type -> :ok end)

    assert :ok = Logs.subscribe_for_new_logs(:node, :type)
  end

  test "unsubscribe_for_new_logs/2" do
    Sentinel.LogsMock
    |> expect(:unsubscribe_for_new_logs, fn _node, _type -> :ok end)

    assert :ok = Logs.unsubscribe_for_new_logs(:node, :type)
  end

  test "list_data_by_node_log_type/2" do
    Sentinel.LogsMock
    |> expect(:list_data_by_node_log_type, fn _node, _type, _options -> [] end)

    assert [] = Logs.list_data_by_node_log_type(:node, :type, [])
  end

  test "get_types_by_node/1" do
    Sentinel.LogsMock
    |> expect(:get_types_by_node, fn _node -> [] end)

    assert [] = Logs.get_types_by_node(:node)
  end

  test "list_active_nodes/0" do
    Sentinel.LogsMock
    |> expect(:list_active_nodes, fn -> [] end)

    assert [] = Logs.list_active_nodes()
  end
end
