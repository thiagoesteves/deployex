defmodule DeployexWeb.Metrics.VmRunQueueTest do
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

  %{
    1 => %{metric: "vm.total_run_queue_lengths.total"},
    2 => %{metric: "vm.total_run_queue_lengths.cpu"},
    3 => %{metric: "vm.total_run_queue_lengths.io"}
  }
  |> Enum.each(fn {element, %{metric: metric}} ->
    test "#{element} - Add/Remove Service + #{metric}", %{conn: conn, node_list: node_list} do
      node = node_list[1] |> to_string
      service_id = String.replace(node, "@", "-")
      metric = unquote(metric)
      metric_id = String.replace(metric, ".", "-")

      Deployex.TelemetryMock
      |> expect(:subscribe_for_new_keys, fn -> :ok end)
      |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [] end)
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
  end)

  %{
    1 => %{metric: "vm.total_run_queue_lengths.total"},
    2 => %{metric: "vm.total_run_queue_lengths.cpu"},
    3 => %{metric: "vm.total_run_queue_lengths.io"}
  }
  |> Enum.each(fn {element, %{metric: metric}} ->
    test "#{element} - #{metric} + Service", %{conn: conn, node_list: node_list} do
      node = node_list[1] |> to_string
      service_id = String.replace(node, "@", "-")
      metric = unquote(metric)
      metric_id = String.replace(metric, ".", "-")

      Deployex.TelemetryMock
      |> expect(:subscribe_for_new_keys, fn -> :ok end)
      |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [] end)
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
  end)

  %{
    1 => %{metric: "vm.total_run_queue_lengths.total", init: 123, update: 456},
    2 => %{metric: "vm.total_run_queue_lengths.cpu", init: 789, update: 10_123},
    3 => %{metric: "vm.total_run_queue_lengths.io", init: 10_456, update: 10_789}
  }
  |> Enum.each(fn {element, %{metric: metric, init: init, update: update}} ->
    test "#{element} - Phoenix Duration - Init and Push #{metric}", %{
      conn: conn,
      node_list: node_list
    } do
      node = node_list[1] |> to_string
      service_id = String.replace(node, "@", "-")
      metric = unquote(metric)
      metric_id = String.replace(metric, ".", "-")

      init = unquote(init)
      update = unquote(update)

      test_pid_process = self()

      Deployex.TelemetryMock
      |> expect(:subscribe_for_new_keys, fn -> :ok end)
      |> expect(:subscribe_for_new_data, fn ^node, ^metric ->
        send(test_pid_process, {:liveview_pid, self()})
        :ok
      end)
      |> expect(:list_data_by_node_key, fn ^node, ^metric, _ ->
        [
          TelemetryFixtures.build_telemetry_data(1_737_982_400_666.0, init)
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
      assert html =~ "2025-01-27 12:53:20.666"
      assert html =~ "#{init}"

      send(
        liveview_pid,
        {:metrics_new_data, node, metric,
         TelemetryFixtures.build_telemetry_data(1_737_982_379_777, update)}
      )

      # assert live updated data
      html = render(liveview)
      assert html =~ "2025-01-27 12:52:59.777Z"
      assert html =~ "#{update}"
    end
  end)
end
