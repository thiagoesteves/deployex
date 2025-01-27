defmodule Deployex.TelemetryTest do
  use ExUnit.Case, async: false

  import Mock

  alias Deployex.Telemetry.Collector
  alias Deployex.TelemetryFixtures

  setup do
    {:ok, hostname} = :inet.gethostname()
    app_name = "testapp"
    instance = 1

    assert {:ok, pid} = Collector.start_link([])

    %{node: :"#{app_name}-#{instance}@#{hostname}", pid: pid}
  end

  test "[un]subscribe_for_new_keys/0", %{node: node} do
    Collector.subscribe_for_new_keys()

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Collector.push_data()

    assert_receive {:metrics_new_keys, ^node, ["vm.memory.total"]}, 1_000
  end

  test "[un]subscribe_for_new_data/0", %{node: node} do
    Collector.subscribe_for_new_data(node, "vm.memory.total")

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Collector.push_data()

    assert_receive {:metrics_new_data, ^node, "vm.memory.total",
                    %Deployex.Telemetry.Data{timestamp: _, unit: _, value: _, measurements: _}},
                   1_000

    # Validate by inspection
    Collector.unsubscribe_for_new_data(node, "vm.memory.total")
  end

  test "get_keys_by_instance/1 valid instance", %{node: node} do
    Collector.subscribe_for_new_data(node, "vm.memory.total")

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Collector.push_data()

    assert_receive {:metrics_new_data, ^node, "vm.memory.total",
                    %Deployex.Telemetry.Data{timestamp: _, unit: _, value: _, measurements: _}},
                   1_000

    assert ["vm.memory.total"] == Collector.get_keys_by_instance(1)
  end

  test "get_keys_by_instance/1 invalid instance" do
    assert [] == Collector.get_keys_by_instance(1000)
  end

  test "list_data_by_instance/3", %{node: node} do
    key_name = "test.phoenix"

    Collector.subscribe_for_new_data(node, key_name)

    Enum.each(1..5, &Collector.push_data(build_metric(node, key_name, &1)))

    assert_receive {:metrics_new_data, ^node, ^key_name, %{timestamp: _, unit: _, value: 5}},
                   1_000

    assert [
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _}
           ] = Collector.list_data_by_instance_key(1, key_name, order: :asc)

    assert [
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _}
           ] = Collector.list_data_by_instance_key(1, key_name, order: :desc)
  end

  test "list_data_by_instance/1", %{node: node} do
    key_name = "test.phoenix"

    Collector.subscribe_for_new_data(node, key_name)

    Enum.each(1..5, &Collector.push_data(build_metric(node, key_name, &1)))

    assert_receive {:metrics_new_data, ^node, ^key_name, %{timestamp: _, unit: _, value: 5}},
                   1_000

    assert [_ | _] = Collector.list_data_by_instance(1)
  end

  test "list_data_by_node_key/3", %{node: node} do
    key_name = "test.phoenix"

    Collector.subscribe_for_new_data(node, key_name)

    Enum.each(1..5, &Collector.push_data(build_metric(node, key_name, &1)))

    assert_receive {:metrics_new_data, ^node, ^key_name, %{timestamp: _, unit: _, value: 5}},
                   1_000

    assert [
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _}
           ] = Collector.list_data_by_node_key(node |> to_string(), key_name, order: :asc)

    assert [
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _}
           ] = Collector.list_data_by_node_key(node |> to_string(), key_name, order: :desc)

    assert [
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _}
           ] = Collector.list_data_by_node_key(node |> to_string(), key_name)
  end

  test "Pruning expiring entries", %{node: node, pid: pid} do
    key_name = "test.phoenix"

    now = System.os_time(:millisecond)

    Collector.subscribe_for_new_data(node, key_name)

    with_mock System, os_time: fn _ -> now - 120_000 end do
      Enum.each(1..5, &Collector.push_data(build_metric(node, key_name, &1)))

      assert_receive {:metrics_new_data, ^node, ^key_name, %{timestamp: _, unit: _, value: 5}},
                     1_000
    end

    assert [
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %Deployex.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _}
           ] = Collector.list_data_by_node_key(node |> to_string(), key_name, order: :asc)

    send(pid, :prune_expired_entries)
    :timer.sleep(100)

    assert [] = Collector.list_data_by_node_key(node |> to_string(), key_name, order: :asc)
  end

  defp build_metric(node, name, value) do
    %{
      metrics: [
        %TelemetryDeployex.Metrics{
          name: name,
          version: "0.1.0-rc2",
          value: value,
          unit: " millisecond",
          info: "",
          tags: %{status: 200, method: "GET"},
          type: "summary"
        }
      ],
      reporter: node,
      measurements: %{duration: 1_311_711}
    }
  end
end
