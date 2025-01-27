defmodule DeployexWeb.Metrics.PhoenixTest do
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
    1 => %{metric: "phoenix.endpoint.start.system_time"},
    2 => %{metric: "phoenix.endpoint.stop.duration"},
    3 => %{metric: "phoenix.router_dispatch.start.system_time"},
    4 => %{metric: "phoenix.router_dispatch.exception.duration"},
    5 => %{metric: "phoenix.router_dispatch.stop.duration"},
    6 => %{metric: "phoenix.socket_connected.duration"},
    7 => %{metric: "phoenix.channel_joined.duration"},
    8 => %{metric: "phoenix.channel_handled_in.duration"}
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
    1 => %{metric: "phoenix.endpoint.start.system_time"},
    2 => %{metric: "phoenix.endpoint.start.system_time"},
    3 => %{metric: "phoenix.endpoint.stop.duration"},
    4 => %{metric: "phoenix.router_dispatch.start.system_time"},
    5 => %{metric: "phoenix.router_dispatch.stop.duration"},
    6 => %{metric: "phoenix.socket_connected.duration"},
    7 => %{metric: "phoenix.channel_joined.duration"}
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
    1 => %{
      metric: "phoenix.endpoint.start.system_time",
      init: 1_737_982_400_400,
      update: 1_737_982_400_600
    },
    2 => %{
      metric: "phoenix.router_dispatch.start.system_time",
      init: 1_737_982_400_400,
      update: 1_737_982_400_600
    }
  }
  |> Enum.each(fn {element, %{metric: metric, init: init, update: update}} ->
    test "#{element} - Phoenix Start - Init and Push #{metric}", %{
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
          TelemetryFixtures.build_telemetry_data(1_737_982_400_500, init)
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
      assert html =~ "2025-01-27T12:53:20.500"
      assert html =~ "2025-01-27T12:53:20.400"

      send(
        liveview_pid,
        {:metrics_new_data, node, metric,
         TelemetryFixtures.build_telemetry_data(1_737_982_400_700, update)}
      )

      # assert live updated data
      html = render(liveview)
      assert html =~ "2025-01-27T12:53:20.700Z"
      assert html =~ "2025-01-27T12:53:20.600Z"
    end
  end)

  %{
    1 => %{metric: "phoenix.endpoint.stop.duration", init: 50.0, update: 60.0},
    2 => %{metric: "phoenix.router_dispatch.stop.duration", init: 70.0, update: 80.0},
    3 => %{metric: "phoenix.router_dispatch.exception.duration", init: 90.0, update: 100.0},
    4 => %{metric: "phoenix.socket_connected.duration", init: 110.0, update: 120.0},
    5 => %{metric: "phoenix.channel_joined.duration", init: 130.0, update: 140.0},
    6 => %{metric: "phoenix.channel_handled_in.duration", init: 150.0, update: 160.0}
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
          TelemetryFixtures.build_telemetry_data(1_737_982_400_666.0, init, " millisecond")
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
      assert html =~ "2025-01-27T12:53:20.666"
      assert html =~ "#{init}"

      send(
        liveview_pid,
        {:metrics_new_data, node, metric,
         TelemetryFixtures.build_telemetry_data(1_737_982_379_777, update)}
      )

      # assert live updated data
      html = render(liveview)
      assert html =~ "2025-01-27T12:52:59.777Z"
      assert html =~ "#{update}"
    end
  end)
end
