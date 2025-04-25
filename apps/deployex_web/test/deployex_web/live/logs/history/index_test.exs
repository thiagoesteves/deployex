defmodule DeployexWeb.Logs.History.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Monitoring
  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias Sentinel.Logs.Message

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user,
    :create_history_logs,
    :add_test_node
  ]

  test "GET /applications check buttom", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live
           |> element("a", "History Logs")
           |> render_click()
  end

  test "GET /logs/history", %{conn: conn, test_node: node} do
    Sentinel.LogsMock
    |> expect(:list_active_nodes, fn -> [node] end)
    |> stub(:get_types_by_node, fn _node -> ["stderr"] end)

    {:ok, _index_live, html} = live(conn, ~p"/logs/history")

    assert html =~ "History Logs"
  end

  test "Add Service + Stdout", %{conn: conn, test_node: node, logs: logs} do
    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Sentinel.LogsMock
    |> stub(:list_active_nodes, fn -> [node] end)
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> expect(:list_data_by_node_log_type, fn ^node, ^log_type, [from: 5] ->
      send(test_pid_process, {:handle_ref_event, ref})
      logs
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/history")

    index_live
    |> element("#logs-history-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-services-#{service_id}-add-item")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert render(index_live) =~ "[info] log 5"
  end

  test "Add Stdout + Service", %{conn: conn, test_node: node, logs: logs} do
    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Sentinel.LogsMock
    |> stub(:list_active_nodes, fn -> [node] end)
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> expect(:list_data_by_node_log_type, fn ^node, ^log_type, [from: 5] ->
      send(test_pid_process, {:handle_ref_event, ref})
      logs
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/history")

    index_live
    |> element("#logs-history-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-services-#{service_id}-add-item")
    |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert render(index_live) =~ "[info] log 5"
  end

  test "Add/Remove Service + Stdout", %{conn: conn, test_node: node, logs: logs} do
    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Sentinel.LogsMock
    |> stub(:list_active_nodes, fn -> [node] end)
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> expect(:list_data_by_node_log_type, fn ^node, ^log_type, [from: 5] ->
      send(test_pid_process, {:handle_ref_event, ref})
      logs
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/history")

    index_live
    |> element("#logs-history-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-services-#{service_id}-add-item")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert render(index_live) =~ "[info] log 5"

    index_live
    |> element("#logs-history-multi-select-services-#{service_id}-remove-item")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-logs-#{log_type}-remove-item")
    |> render_click()

    refute render(index_live) =~ "[info] log 5"
  end

  test "Add/Remove Stdout + Service", %{conn: conn, test_node: node, logs: logs} do
    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Sentinel.LogsMock
    |> stub(:list_active_nodes, fn -> [node] end)
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> expect(:list_data_by_node_log_type, fn ^node, ^log_type, [from: 5] ->
      send(test_pid_process, {:handle_ref_event, ref})
      logs
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/history")

    index_live
    |> element("#logs-history-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-services-#{service_id}-add-item")
    |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000

    assert render(index_live) =~ "[info] log 5"

    index_live
    |> element("#logs-history-multi-select-logs-#{log_type}-remove-item")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-services-#{service_id}-remove-item")
    |> render_click()

    refute render(index_live) =~ "[info] log 5"
  end

  test "Start Time select button", %{conn: conn, test_node: node, logs: logs} do
    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Sentinel.LogsMock
    |> stub(:list_active_nodes, fn -> [node] end)
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> stub(:list_data_by_node_log_type, fn
      ^node, ^log_type, [from: 1] ->
        logs

      ^node, ^log_type, [from: 5] ->
        logs

      ^node, ^log_type, [from: 15] ->
        logs

      ^node, ^log_type, [from: 30] ->
        logs

      ^node, ^log_type, [from: 60] ->
        send(test_pid_process, {:handle_ref_event, ref})
        logs
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/history")

    index_live
    |> element("#logs-history-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    index_live
    |> element("#logs-history-multi-select-services-#{service_id}-add-item")
    |> render_click()

    time = "1m"

    index_live
    |> element("#logs-history-update-form")
    |> render_change(%{start_time: time}) =~ time

    time = "5m"

    index_live
    |> element("#logs-history-update-form")
    |> render_change(%{start_time: time}) =~ time

    time = "15m"

    index_live
    |> element("#logs-history-update-form")
    |> render_change(%{start_time: time}) =~ time

    time = "30m"

    index_live
    |> element("#logs-history-update-form")
    |> render_change(%{start_time: time}) =~ time

    time = "1h"

    index_live
    |> element("#logs-history-update-form")
    |> render_change(%{start_time: time}) =~ time

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  defp create_history_logs(context) do
    logs = [
      %Message{timestamp: System.os_time(:millisecond), log: "[info] log 1"},
      %Message{timestamp: System.os_time(:millisecond), log: "[info] log 2"},
      %Message{timestamp: System.os_time(:millisecond), log: "[info] log 3"},
      %Message{timestamp: System.os_time(:millisecond), log: "[info] log 4"},
      %Message{timestamp: System.os_time(:millisecond), log: "[info] log 5"}
    ]

    Map.put(context, :logs, logs)
  end
end
