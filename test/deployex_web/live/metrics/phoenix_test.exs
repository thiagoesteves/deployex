defmodule DeployexWeb.Metrics.PhoenixTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user,
    :node_list
  ]

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
    test "#{element} - Add/Remove Service + #{metric}", %{conn: conn, node_list: node_list} do
      node = node_list[1] |> to_string
      service_id = String.replace(node, "@", "-")
      metric = unquote(metric)
      metric_id = String.replace(metric, ".", "-")

      test_pid_process = self()

      Deployex.TelemetryMock
      |> expect(:subscribe_for_new_keys, fn -> :ok end)
      |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [] end)
      |> stub(:node_by_instance, fn instance ->
        if instance == 3, do: send(test_pid_process, {:liveview_pid, self()})
        node_list[instance]
      end)
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

      test_pid_process = self()

      Deployex.TelemetryMock
      |> expect(:subscribe_for_new_keys, fn -> :ok end)
      |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [] end)
      |> stub(:node_by_instance, fn instance ->
        if instance == 3, do: send(test_pid_process, {:liveview_pid, self()})
        node_list[instance]
      end)
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
end
