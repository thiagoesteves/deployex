defmodule DeployexWeb.Logs.Live.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user,
    :add_test_node
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
           |> element("a", "Live Logs")
           |> render_click()
  end

  test "GET /logs/live", %{conn: conn} do
    Deployex.LogsMock
    |> stub(:get_types_by_node, fn _node -> ["stderr"] end)

    {:ok, _index_live, html} = live(conn, ~p"/logs/live")

    assert html =~ "Live Logs"
  end

  test "Add Service + Stdout", %{conn: conn, test_node: node} do
    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Deployex.LogsMock
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> expect(:subscribe_for_new_logs, fn ^node, ^log_type ->
      send(test_pid_process, {:handle_ref_event, ref})
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/live")

    index_live
    |> element("#logs-live-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-services-#{service_id}-add-item")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Add Stdout + Service", %{conn: conn, test_node: node} do
    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Deployex.LogsMock
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> expect(:subscribe_for_new_logs, fn ^node, ^log_type ->
      send(test_pid_process, {:handle_ref_event, ref})
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/live")

    index_live
    |> element("#logs-live-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-services-#{service_id}-add-item")
    |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Add/Remove Service + Stdout", %{conn: conn, test_node: node} do
    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Deployex.LogsMock
    |> expect(:subscribe_for_new_logs, fn _node, _log_type -> :ok end)
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> expect(:unsubscribe_for_new_logs, fn ^node, ^log_type ->
      send(test_pid_process, {:handle_ref_event, ref})
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/live")

    index_live
    |> element("#logs-live-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-services-#{service_id}-add-item")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-services-#{service_id}-remove-item")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-logs-#{log_type}-remove-item")
    |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Add/Remove Stdout + Service", %{conn: conn, test_node: node} do
    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Deployex.LogsMock
    |> expect(:subscribe_for_new_logs, fn _node, _log_type -> :ok end)
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> expect(:unsubscribe_for_new_logs, fn ^node, ^log_type ->
      send(test_pid_process, {:handle_ref_event, ref})
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/live")

    index_live
    |> element("#logs-live-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-services-#{service_id}-add-item")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-logs-#{log_type}-remove-item")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-services-#{service_id}-remove-item")
    |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  %{
    1 => %{type: "debug", color: "#E5E5E5"},
    2 => %{type: "DEBUG", color: "#E5E5E5"},
    3 => %{type: "info", color: "#93C5FD"},
    4 => %{type: "INFO", color: "#93C5FD"},
    5 => %{type: "warning", color: "#FBBF24"},
    6 => %{type: "WARNING", color: "#FBBF24"},
    7 => %{type: "error", color: "#F87171"},
    8 => %{type: "ERROR", color: "#F87171"},
    9 => %{type: "SIGTERM", color: "#F87171"},
    10 => %{type: "notice", color: "#FDBA74"},
    11 => %{type: "NOTICE", color: "#FDBA74"},
    12 => %{type: "none", color: "#E5E5E5"}
  }
  |> Enum.each(fn {element, %{type: type, color: color}} ->
    test "#{element} - Send Stdout #{type} message from erlexec server", %{
      conn: conn,
      test_node: node
    } do
      message = unquote(type)
      expected_color = unquote(color)

      service_id = String.replace(node, "@", "-")
      log_type = "stdout"
      test_pid_process = self()
      ref = make_ref()

      Deployex.LogsMock
      |> stub(:get_types_by_node, fn _node -> [log_type] end)
      |> expect(:subscribe_for_new_logs, fn ^node, ^log_type ->
        send(test_pid_process, {:handle_ref_event, ref, self()})
        :ok
      end)

      {:ok, index_live, _html} = live(conn, ~p"/logs/live")

      index_live
      |> element("#logs-live-multi-select-toggle-options")
      |> render_click()

      index_live
      |> element("#logs-live-multi-select-services-#{service_id}-add-item")
      |> render_click()

      index_live
      |> element("#logs-live-multi-select-logs-#{log_type}-add-item")
      |> render_click()

      assert_receive {:handle_ref_event, ^ref, liveview_pid}, 1_000

      data = %Deployex.Logs.Message{log: message}
      send(liveview_pid, {:logs_new_data, node, log_type, data})

      assert render(index_live) =~ expected_color
    end
  end)

  test "Reset Stream button", %{conn: conn, test_node: node} do
    message = "my-debug-msg"

    service_id = String.replace(node, "@", "-")
    log_type = "stdout"
    test_pid_process = self()
    ref = make_ref()

    Deployex.LogsMock
    |> stub(:get_types_by_node, fn _node -> [log_type] end)
    |> expect(:subscribe_for_new_logs, fn ^node, ^log_type ->
      send(test_pid_process, {:handle_ref_event, ref, self()})
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs/live")

    index_live
    |> element("#logs-live-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-services-#{service_id}-add-item")
    |> render_click()

    index_live
    |> element("#logs-live-multi-select-logs-#{log_type}-add-item")
    |> render_click()

    assert_receive {:handle_ref_event, ^ref, liveview_pid}, 1_000

    data = %Deployex.Logs.Message{log: message}
    send(liveview_pid, {:logs_new_data, node, log_type, data})

    assert render(index_live) =~ message

    index_live
    |> element("#logs-live-multi-select-reset", "RESET")
    |> render_click()

    refute render(index_live) =~ message
  end
end
