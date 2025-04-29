defmodule Sentinel.Monitoring.BeamVmTest do
  use ExUnit.Case, async: false

  import Mox

  alias Sentinel.Monitoring.BeamVm.Server, as: BeamVmServer

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "start_link/1" do
    name = "#{__MODULE__}-001" |> String.to_atom()

    assert {:ok, _pid} = BeamVmServer.start_link(name: name, update_info_interval: 100)
  end

  test "subscribe/0" do
    name = "#{__MODULE__}-002" |> String.to_atom()

    assert {:ok, _pid} = BeamVmServer.start_link(name: name, update_info_interval: 10)

    BeamVmServer.subscribe()

    assert_receive {:beam_vm_update_statistics, %{}}, 1_000
  end

  test "nodeup - expected node" do
    name = "#{__MODULE__}-003" |> String.to_atom()
    test_pid_process = self()
    ref = make_ref()
    expected_memory = 5_555
    expected_count = 9_999

    assert {:ok, pid} = BeamVmServer.start_link(name: name, update_info_interval: 10)

    node = Foundation.Catalog.expected_nodes() |> hd

    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :erlang, :memory, [], _timeout ->
        Process.send_after(test_pid_process, {:handle_ref_event, ref}, 10)
        [total: expected_memory]

      ^node, :erlang, :system_info, _params, _timeout ->
        expected_count
    end)

    send(pid, {:nodeup, node})

    assert_receive {:handle_ref_event, ^ref}, 1_000

    BeamVmServer.subscribe()

    assert_receive {:beam_vm_update_statistics, %{statistics: statistics}}, 1_000

    assert %{
             port_count: ^expected_count,
             port_limit: ^expected_count,
             process_count: ^expected_count,
             process_limit: ^expected_count,
             atom_count: ^expected_count,
             atom_limit: ^expected_count,
             total_memory: ^expected_memory
           } = Map.get(statistics, node)
  end

  test "nodeup - expected node - rpc error" do
    name = "#{__MODULE__}-004" |> String.to_atom()
    test_pid_process = self()
    ref = make_ref()

    assert {:ok, pid} = BeamVmServer.start_link(name: name, update_info_interval: 10)

    node = Foundation.Catalog.expected_nodes() |> hd

    Foundation.RpcMock
    |> stub(:call, fn
      _node, _module, _function, _args, _timeout ->
        Process.send_after(test_pid_process, {:handle_ref_event, ref}, 10)
        :badrpc
    end)

    send(pid, {:nodeup, node})

    assert_receive {:handle_ref_event, ^ref}, 1_000

    BeamVmServer.subscribe()

    assert_receive {:beam_vm_update_statistics, %{statistics: statistics}}, 1_000

    assert %{
             port_count: nil,
             port_limit: nil,
             process_count: nil,
             process_limit: nil,
             atom_count: nil,
             atom_limit: nil,
             total_memory: nil
           } = Map.get(statistics, node)
  end

  test "nodeup - invalid node" do
    name = "#{__MODULE__}-005" |> String.to_atom()
    assert {:ok, pid} = BeamVmServer.start_link(name: name, update_info_interval: 10)

    send(pid, {:nodeup, :invalid@node})

    assert %{nodes: []} = :sys.get_state(name)
  end

  test "nodedown - expected node" do
    name = "#{__MODULE__}-006" |> String.to_atom()
    assert {:ok, pid} = BeamVmServer.start_link(name: name, update_info_interval: 10)

    node = Foundation.Catalog.expected_nodes() |> hd

    send(pid, {:nodeup, node})

    assert %{nodes: [_]} = :sys.get_state(name)

    send(pid, {:nodedown, node})

    assert %{nodes: []} = :sys.get_state(name)
  end

  test "nodedown - invalid node" do
    name = "#{__MODULE__}-007" |> String.to_atom()

    assert {:ok, pid} = BeamVmServer.start_link(name: name, update_info_interval: 10)

    node = Foundation.Catalog.expected_nodes() |> hd

    Foundation.RpcMock
    |> stub(:call, fn _node, _module, _function, _args, _timeout -> :badrpc end)

    send(pid, {:nodedown, :invalid@node})
    send(pid, {:nodeup, node})

    wait_all_messages(name)

    assert %{nodes: [^node]} = :sys.get_state(name)
  end

  # Note: Fetching the state guarantees that previous messages will be executed
  defp wait_all_messages(name) do
    %{expected_nodes: _expected_nodes} = :sys.get_state(name)
  end
end
