defmodule DeployexWeb.Applications.LogsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus
  alias Deployex.Fixture.Terminal, as: FixtureTerminal

  test "Access to stdout logs by instance", %{conn: conn} do
    topic = "topic-logs-000"

    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-log-stdout-1") |> render_click() =~
             "Application Logs [1]"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Access to stderr logs by instance", %{conn: conn} do
    topic = "topic-logs-001"

    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-log-stderr-1") |> render_click() =~
             "Application Logs [1]"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Redirect received string to JS", %{conn: conn} do
    topic = "topic-logs-002"

    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-log-stdout-1") |> render_click() =~
             "Application Logs [1]"

    message = "[info] my-info-message"
    update_log_message(os_pid, message)

    assert render(index_live) =~ message
    assert render(index_live) =~ "text-blue-500"

    message = "[debug] my-debug-message"
    update_log_message(os_pid, message)

    assert render(index_live) =~ message
    assert render(index_live) =~ "text-gray-700"

    message = "[warning] my-warning-message"
    update_log_message(os_pid, message)

    assert render(index_live) =~ message
    assert render(index_live) =~ "text-yellow-700"

    message = "[error] my-error-message"
    update_log_message(os_pid, message)

    assert render(index_live) =~ message
    assert render(index_live) =~ "text-red-700"

    message = "[notice] my-notice-message"
    update_log_message(os_pid, message)

    assert render(index_live) =~ message
    assert render(index_live) =~ "text-orange-700"

    message = "[not-defined] my-default-message"
    update_log_message(os_pid, message)

    assert render(index_live) =~ message
    assert render(index_live) =~ "text-gray-700"

    message = "my-default-message"
    update_log_message(os_pid, message)

    assert render(index_live) =~ message
    assert render(index_live) =~ "text-gray-700"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Error accessing deployex logs [this logs are available ony in production]", %{conn: conn} do
    topic = "topic-logs-003"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert html = index_live |> element("#app-log-stdout-0") |> render_click()
    assert html =~ "Application Logs [0]"
    assert html =~ "File not found"
  end

  defp update_log_message(os_pid, message) do
    [pid] = FixtureTerminal.list_children()
    send(pid, {:stdout, os_pid, "\rtime #{message}"})
    # Wait the page for the update
    :timer.sleep(10)
  end
end
