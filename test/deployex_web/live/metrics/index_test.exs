defmodule DeployexWeb.Metrics.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus
  alias Deployex.TelemetryFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user,
    :node_list
  ]

  test "GET /applications check buttom", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live
           |> element("a", "Live Metrics")
           |> render_click()
  end

  test "GET /metrics", %{conn: conn, node_list: node_list} do
    test_pid_process = self()

    Deployex.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> stub(:node_by_instance, fn instance ->
      if instance == 3, do: send(test_pid_process, {:liveview_pid, self()})
      node_list[instance]
    end)
    |> stub(:get_keys_by_instance, fn _ -> [] end)

    {:ok, _index_live, html} = live(conn, ~p"/metrics")

    assert_receive {:liveview_pid, _liveview_pid}, 1_000

    assert html =~ "Live Metrics"
  end

  test "GET /metrics + new key", %{conn: conn, node_list: node_list} do
    test_pid_process = self()

    metric = "fake.phoenix.metric"

    Deployex.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> stub(:node_by_instance, fn instance ->
      if instance == 3, do: send(test_pid_process, {:liveview_pid, self()})
      node_list[instance]
    end)
    |> stub(:get_keys_by_instance, fn _instance ->
      # 0, 1, 2, 3: return []
      # > 3: return [metric]
      called = Process.get("get_keys_by_instance", 0)
      Process.put("get_keys_by_instance", called + 1)

      if called > 3 do
        send(test_pid_process, :added_metric)
        [metric]
      else
        []
      end
    end)

    {:ok, liveview, html} = live(conn, ~p"/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    assert_receive {:liveview_pid, liveview_pid}, 1_000

    refute html =~ "#{metric}"

    send(liveview_pid, {:metrics_new_keys, nil, nil})

    assert_receive :added_metric, 1_000

    html = render(liveview)

    assert html =~ "#{metric}"
  end

  test "GET /metrics + update form", %{conn: conn, node_list: node_list} do
    node = node_list[1] |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "vm.memory.total"
    metric_id = String.replace(metric, ".", "-")

    test_pid_process = self()

    Deployex.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> stub(:list_data_by_node_key, fn ^node, ^metric, _ ->
      [
        TelemetryFixtures.build_telemetry_data_vm_total_memory(),
        TelemetryFixtures.build_telemetry_data_vm_total_memory(),
        TelemetryFixtures.build_telemetry_data_vm_total_memory()
      ]
    end)
    |> stub(:node_by_instance, fn instance ->
      if instance == 3, do: send(test_pid_process, {:liveview_pid, self()})
      node_list[instance]
    end)
    |> stub(:get_keys_by_instance, fn _instance -> [metric] end)

    {:ok, liveview, _html} = live(conn, ~p"/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-metrics-#{metric_id}-add-item")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-services-#{service_id}-add-item")
    |> render_click()

    assert_receive {:liveview_pid, _liveview_pid}, 1_000

    time = "1 minute"

    liveview
    |> element("#metrics-update-form")
    |> render_change(%{num_cols: 1, start_time: time}) =~ time

    time = "5 minutes"

    liveview
    |> element("#metrics-update-form")
    |> render_change(%{num_cols: 2, start_time: time}) =~ time

    time = "15 minutes"

    liveview
    |> element("#metrics-update-form")
    |> render_change(%{num_cols: 3, start_time: time}) =~ time

    time = "30 minutes"

    liveview
    |> element("#metrics-update-form")
    |> render_change(%{num_cols: 4, start_time: time}) =~ time
  end
end
