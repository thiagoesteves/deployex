defmodule Deployer.ResourcesTest do
  use ExUnit.Case, async: false

  import Mox

  alias Deployer.Resources
  alias Deployer.Resources.Limit
  alias Deployer.Resources.Server
  alias Foundation.Catalog

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    name = :"resources_test_#{System.unique_integer([:positive])}"
    sname = Catalog.create_sname("myelixir")
    node = Catalog.node_info(sname).node

    %{name: name, sname: sname, node: node}
  end

  defp start_server(name), do: start_supervised!({Server, name: name, sample_interval: :manual})

  defp sample(name), do: GenServer.call(name, :sample)

  defp stub_running(sname, status \\ :running) do
    Deployer.MonitorMock
    |> stub(:list, fn -> [sname] end)
    |> stub(:state, fn ^sname -> %Deployer.Monitor{sname: sname, status: status} end)
  end

  # Answers the RPCs as an instance with these counts and this runtime counter
  defp stub_node(node, counts, runtime_ms) do
    Foundation.RpcMock
    |> stub(:call, fn
      ^node, :erlang, :statistics, [:runtime], _timeout -> {runtime_ms.(), 0}
      ^node, :os, :getpid, [], _timeout -> ~c"4242"
      ^node, :erlang, :system_info, [key], _timeout -> Map.fetch!(counts, key)
    end)
  end

  defp stub_ps(output) do
    stub(Host.CommanderMock, :run, fn "ps -o pid=,rss= -p 4242", [:sync, :stdout] -> output end)
  end

  @counts %{
    process_count: 812,
    process_limit: 1_000,
    port_count: 40,
    port_limit: 65_536,
    atom_count: 30_000,
    atom_limit: 1_048_576
  }

  test "samples the memory, counts and limits of a running instance", %{
    name: name,
    sname: sname,
    node: node
  } do
    stub_running(sname)
    stub_node(node, @counts, fn -> 1_000 end)
    stub_ps({:ok, [stdout: ["  4242  204800\n"]]})
    start_server(name)

    :ok = sample(name)

    assert %Resources{
             sname: ^sname,
             cpu: nil,
             memory: 209_715_200,
             process: %Limit{count: 812, limit: 1_000, percent: 81, change_percent: nil},
             port: %Limit{count: 40, percent: 0},
             atom: %Limit{count: 30_000, limit: 1_048_576, percent: 2},
             sampled_at: %DateTime{}
           } = Server.get(sname, name)
  end

  test "computes the CPU share from the runtime counter between two samples", %{
    name: name,
    sname: sname,
    node: node
  } do
    counter = :counters.new(1, [])
    stub_running(sname)

    stub_node(node, @counts, fn ->
      # Each sample reads 10 seconds of CPU time more than the one before
      :counters.add(counter, 1, 10_000)
      :counters.get(counter, 1)
    end)

    stub_ps({:ok, [stdout: ["4242 1024\n"]]})
    start_server(name)

    :ok = sample(name)
    Process.sleep(20)
    :ok = sample(name)

    assert %Resources{cpu: cpu} = Server.get(sname, name)
    assert is_integer(cpu) and cpu > 0
  end

  test "keeps the sample with no memory when ps fails", %{name: name, sname: sname, node: node} do
    stub_running(sname)
    stub_node(node, @counts, fn -> 1_000 end)
    stub_ps({:error, [exit_status: 256]})
    start_server(name)

    :ok = sample(name)

    assert %Resources{memory: nil, process: %Limit{count: 812}} = Server.get(sname, name)
  end

  test "removes an instance that does not answer", %{name: name, sname: sname, node: node} do
    stub_running(sname)
    stub_node(node, @counts, fn -> 1_000 end)
    stub_ps({:ok, [stdout: ["4242 1024\n"]]})
    start_server(name)

    :ok = sample(name)
    assert %Resources{} = Server.get(sname, name)

    stub(Foundation.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
      {:badrpc, :timeout}
    end)

    send(Process.whereis(name), :sample)
    :sys.get_state(name)

    assert Server.get(sname, name) == nil
  end

  test "skips an instance that is not running", %{name: name, sname: sname} do
    stub_running(sname, :starting)
    start_server(name)

    :ok = sample(name)

    assert Server.get(sname, name) == nil
  end

  test "reports how a count changed over the minutes it kept", %{
    name: name,
    sname: sname,
    node: node
  } do
    stub_running(sname)
    stub_node(node, %{@counts | atom_count: 34_500}, fn -> 1_000 end)
    stub_ps({:ok, [stdout: ["4242 1024\n"]]})
    start_server(name)

    # A series that started 45 minutes ago with 30,000 atoms
    minute = div(System.os_time(:second), 60)

    :sys.replace_state(name, fn state ->
      instance = %{
        node: node,
        os_pid: 4242,
        runtime_ms: 0,
        at_ms: System.monotonic_time(:millisecond),
        counts: @counts,
        history: [{minute - 45, @counts}]
      }

      %{state | instances: %{sname => instance}}
    end)

    :ok = sample(name)

    assert %Resources{atom: %Limit{count: 34_500, change_percent: 15, change_minutes: 45}} =
             Server.get(sname, name)
  end

  test "returns nil with no server" do
    assert Server.get("myelixir-abc", :no_such_resources_server) == nil
    assert Resources.get("myelixir-abc") == nil
  end
end
