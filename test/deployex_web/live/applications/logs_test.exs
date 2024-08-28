defmodule DeployexWeb.Applications.LogsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.Fixture.Monitoring
  alias Deployex.Terminal.Server

  test "Access to stdout logs by instance", %{conn: conn} do
    topic = "topic-logs-000"

    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)

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

    assert :ok =
             Server.async_terminate(%Deployex.Terminal.Server{instance: "1", type: :logs_stdout})

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

    assert :ok =
             Server.async_terminate(%Deployex.Terminal.Server{instance: "1", type: :logs_stderr})

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

    assert :ok =
             Server.async_terminate(%Deployex.Terminal.Server{instance: "1", type: :logs_stdout})

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Maximum number of logs reached", %{conn: conn} do
    topic = "topic-logs-003"

    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    assert capture_log(fn ->
             assert {:ok, _pid} =
                      Deployex.Terminal.Supervisor.new(%Deployex.Terminal.Server{
                        instance: "1",
                        commands: "",
                        options: [],
                        target: self(),
                        type: :logs_stdout
                      })

             {:ok, index_live, _html} = live(conn, ~p"/applications")

             assert index_live |> element("#app-log-stdout-1") |> render_click() =~
                      "Application Logs [1]"

             assert :ok =
                      Server.async_terminate(%Deployex.Terminal.Server{
                        instance: "1",
                        type: :logs_stdout
                      })

             assert_receive {:handle_ref_event, ^ref}, 1_000
           end) =~ "Maximum number of log terminals achieved for instance: 1 type: logs_stdout"
  end

  defp update_log_message(os_pid, message) do
    pid = :global.whereis_name(%{type: :logs_stdout, instance: "1"})
    send(pid, {:stdout, os_pid, "\rtime #{message}"})
    # Wait the page for the update
    :timer.sleep(10)
  end
end
