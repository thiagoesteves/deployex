defmodule DeployexWeb.Metrics.VmMemoryTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Deployex.TelemetryFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user,
    :node_list
  ]

  test "Add/Remove Service + vm.memory.total", %{conn: conn, node_list: node_list} do
    node = node_list[1] |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "vm.memory.total"
    metric_id = String.replace(metric, ".", "-")
    telemetry_data = TelemetryFixtures.build_telemetry_data_vm_total_memory()

    Deployex.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [telemetry_data] end)
    |> stub(:node_by_instance, fn instance -> node_list[instance] end)
    |> stub(:get_keys_by_instance, fn _ -> [metric] end)

    {:ok, liveview, _html} = live(conn, ~p"/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-services-#{service_id}-add-item")
    |> render_click()

    html =
      liveview
      |> element("#metrics-multi-select-metrics-#{metric_id}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "metrics:#{metric}"

    html =
      liveview
      |> element("#metrics-multi-select-services-#{service_id}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    assert html =~ "metrics:#{metric}"

    html =
      liveview
      |> element("#metrics-multi-select-metrics-#{metric_id}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "metrics:#{metric}"
  end

  test "Add/Remove vm.memory.total + Service", %{conn: conn, node_list: node_list} do
    node = node_list[1] |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "vm.memory.total"
    metric_id = String.replace(metric, ".", "-")
    telemetry_data = TelemetryFixtures.build_telemetry_data_vm_total_memory()

    Deployex.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [telemetry_data] end)
    |> stub(:node_by_instance, fn instance -> node_list[instance] end)
    |> stub(:get_keys_by_instance, fn _ -> [metric] end)

    {:ok, liveview, _html} = live(conn, ~p"/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-metrics-#{metric_id}-add-item")
    |> render_click()

    html =
      liveview
      |> element("#metrics-multi-select-services-#{service_id}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "metrics:#{metric}"

    html =
      liveview
      |> element("#metrics-multi-select-metrics-#{metric_id}-remove-item")
      |> render_click()

    assert html =~ "services:#{node}"
    refute html =~ "metrics:#{metric}"

    html =
      liveview
      |> element("#metrics-multi-select-services-#{service_id}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "metrics:#{metric}"
  end

  test "Init and Push vm.memory.total data", %{conn: conn, node_list: node_list} do
    node = node_list[1] |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "vm.memory.total"
    metric_id = String.replace(metric, ".", "-")

    test_pid_process = self()

    Deployex.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ ->
      [
        TelemetryFixtures.build_telemetry_data_vm_total_memory(1_737_982_379_123)
      ]
    end)
    |> stub(:node_by_instance, fn instance -> node_list[instance] end)
    |> stub(:get_keys_by_instance, fn _ -> [metric] end)

    {:ok, liveview, _html} = live(conn, ~p"/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-metrics-#{metric_id}-add-item")
    |> render_click()

    html =
      liveview
      |> element("#metrics-multi-select-services-#{service_id}-add-item")
      |> render_click()

    assert_receive {:liveview_pid, liveview_pid}, 1_000

    # assert initial data
    assert html =~ "2025-01-27 12:52:59.123Z"

    send(
      liveview_pid,
      {:metrics_new_data, node, metric,
       TelemetryFixtures.build_telemetry_data_vm_total_memory(1_737_982_379_456)}
    )

    # assert live updated data
    html = render(liveview)
    assert html =~ "2025-01-27 12:52:59.456Z"
  end
end
