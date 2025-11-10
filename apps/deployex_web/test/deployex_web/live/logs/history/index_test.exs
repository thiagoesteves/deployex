defmodule DeployexWeb.Logs.History.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias DeployexWeb.Helper
  alias Foundation.Catalog
  alias Sentinel.Logs.Message

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user,
    :create_history_logs
  ]

  test "GET /applications check button", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live
           |> element(~s{[href="/logs/history"]})
           |> render_click()
  end

  test "GET /logs/history", %{conn: conn} do
    sname = Catalog.create_sname("test_app")

    Deployer.MonitorMock
    |> stub(:list, fn -> [sname] end)

    Sentinel.LogsMock
    |> expect(:list_active_snames, fn -> [sname] end)
    |> stub(:get_types_by_sname, fn _sname -> ["stderr"] end)

    {:ok, _index_live, html} = live(conn, ~p"/logs/history")

    assert html =~ "History Logs"
  end

  test "Add Service + Stdout", %{conn: conn, logs: logs} do
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()
    name = "test_app"
    sname = Catalog.create_sname(name)
    service_id = Helper.normalize_id(sname)

    Deployer.MonitorMock
    |> stub(:list, fn -> [sname] end)

    Sentinel.LogsMock
    |> stub(:list_active_snames, fn -> [sname] end)
    |> stub(:get_types_by_sname, fn _sname -> [log_type] end)
    |> expect(:list_data_by_sname_log_type, fn ^sname, ^log_type, [from: 5] ->
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

  test "Add Stdout + Service", %{conn: conn, logs: logs} do
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()
    name = "test_app"
    sname = Catalog.create_sname(name)
    service_id = Helper.normalize_id(sname)

    Deployer.MonitorMock
    |> stub(:list, fn -> [sname] end)

    Sentinel.LogsMock
    |> stub(:list_active_snames, fn -> [sname] end)
    |> stub(:get_types_by_sname, fn _sname -> [log_type] end)
    |> expect(:list_data_by_sname_log_type, fn ^sname, ^log_type, [from: 5] ->
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

  test "Add/Remove Service + Stdout", %{conn: conn, logs: logs} do
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()
    name = "test_app"
    sname = Catalog.create_sname(name)
    service_id = Helper.normalize_id(sname)

    Deployer.MonitorMock
    |> stub(:list, fn -> [sname] end)

    Sentinel.LogsMock
    |> stub(:list_active_snames, fn -> [sname] end)
    |> stub(:get_types_by_sname, fn _sname -> [log_type] end)
    |> expect(:list_data_by_sname_log_type, fn ^sname, ^log_type, [from: 5] ->
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

  test "Add/Remove Stdout + Service", %{conn: conn, logs: logs} do
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()
    name = "test_app"
    sname = Catalog.create_sname(name)
    service_id = Helper.normalize_id(sname)

    Deployer.MonitorMock
    |> stub(:list, fn -> [sname] end)

    Sentinel.LogsMock
    |> stub(:list_active_snames, fn -> [sname] end)
    |> stub(:get_types_by_sname, fn _sname -> [log_type] end)
    |> expect(:list_data_by_sname_log_type, fn ^sname, ^log_type, [from: 5] ->
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

  test "Start Time select button", %{conn: conn, logs: logs} do
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()
    name = "test_app"
    sname = Catalog.create_sname(name)
    service_id = Helper.normalize_id(sname)

    Deployer.MonitorMock
    |> stub(:list, fn -> [sname] end)

    Sentinel.LogsMock
    |> stub(:list_active_snames, fn -> [sname] end)
    |> stub(:get_types_by_sname, fn _sname -> [log_type] end)
    |> stub(:list_data_by_sname_log_type, fn
      ^sname, ^log_type, [from: 10_080] ->
        send(test_pid_process, {:handle_ref_event, ref})
        logs

      ^sname, ^log_type, [from: from] when from in [1, 5, 15, 30, 360, 720, 1_440, 4_320] ->
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

    time = "6h"

    index_live
    |> element("#logs-history-update-form")
    |> render_change(%{start_time: time}) =~ time

    assert_receive {:handle_ref_event, ^ref}, 1_000

    time = "12h"

    index_live
    |> element("#logs-history-update-form")
    |> render_change(%{start_time: time}) =~ time

    assert_receive {:handle_ref_event, ^ref}, 1_000

    time = "1d"

    index_live
    |> element("#logs-history-update-form")
    |> render_change(%{start_time: time}) =~ time

    assert_receive {:handle_ref_event, ^ref}, 1_000

    time = "3d"

    index_live
    |> element("#logs-history-update-form")
    |> render_change(%{start_time: time}) =~ time

    assert_receive {:handle_ref_event, ^ref}, 1_000

    time = "1w"

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
