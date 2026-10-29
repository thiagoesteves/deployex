defmodule DeployexWeb.Logs.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Foundation.Catalog
  alias Sentinel.Logs.Message

  setup [:set_mox_global, :verify_on_exit!, :log_in_default_user]

  setup do
    sname = Catalog.create_sname("myelixir")
    %{sname: sname}
  end

  defp message(log, seconds_ago \\ 30),
    do: %Message{timestamp: System.os_time(:millisecond) - seconds_ago * 1_000, log: log}

  # The log server tails stdout and stderr of each source, unless untracked lists it
  defp stub_logs(test_pid, stored, untracked \\ []) do
    Sentinel.LogsMock
    |> stub(:get_types_by_sname, fn sname ->
      if sname in untracked, do: [], else: ["stdout", "stderr"]
    end)
    |> stub(:subscribe_for_new_logs, fn sname, type ->
      send(test_pid, {:subscribed, sname, type})
      :ok
    end)
    |> stub(:unsubscribe_for_new_logs, fn sname, type ->
      send(test_pid, {:unsubscribed, sname, type})
      :ok
    end)
    |> stub(:list_data_by_sname_log_type, fn sname, type, options ->
      send(test_pid, {:read, sname, type, options[:from]})
      Map.get(stored, {sname, type}, [])
    end)
  end

  @tag :capture_log
  test "Live opens with the recent lines of every source, then follows new ones", %{
    conn: conn,
    sname: sname
  } do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)

    stub_logs(self(), %{
      {sname, "stdout"} => [message("GET / [info] Sent 200\nsecond line")],
      {"deployex", "stderr"} => [message("[error] boom", 10)]
    })

    {:ok, view, html} = live(conn, ~p"/logs/live")

    assert html =~ "Logs"
    assert html =~ ~s(aria-pressed="true")
    assert html =~ "Streaming"
    assert html =~ "GET / [info] Sent 200"
    assert html =~ "second line"
    assert html =~ "[error] boom"
    assert html =~ " of 3 sources"
    assert_received {:read, ^sname, "stdout", 5}
    assert_received {:subscribed, ^sname, "stderr"}

    send(view.pid, {:logs_new_data, sname, "stdout", message("a new line", 0)})
    assert render(view) =~ "a new line"
  end

  @tag :capture_log
  test "Pause keeps the new lines for Resume, and Clear empties the view", %{
    conn: conn,
    sname: sname
  } do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("stored line")]})

    {:ok, view, _html} = live(conn, ~p"/logs/live")

    html = view |> element("#logs-pause") |> render_click()
    assert html =~ "Paused"

    send(view.pid, {:logs_new_data, sname, "stdout", message("during the pause", 0)})
    refute render(view) =~ "during the pause"

    html = view |> element("#logs-pause") |> render_click()
    assert html =~ "during the pause"
    assert html =~ "Streaming"

    html = view |> element("#logs-clear") |> render_click()
    refute html =~ "stored line"
    assert html =~ "No lines yet. New lines show here as they arrive."
  end

  @tag :capture_log
  test "the filter keeps the matching lines and marks the match", %{conn: conn, sname: sname} do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("first <b>Error</b> here\nall good")]})

    {:ok, view, _html} = live(conn, ~p"/logs/live")

    html = view |> element("#logs-filter") |> render_change(%{"filter" => "error"})
    assert html =~ ~s(<mark class="dx-mark">Error</mark>)
    assert html =~ "&lt;b&gt;"
    refute html =~ "all good"

    html = view |> element("#logs-filter") |> render_change(%{"filter" => ""})
    assert html =~ "all good"
  end

  @tag :capture_log
  test "a source or a stream can be turned off and back on", %{conn: conn, sname: sname} do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)

    stub_logs(self(), %{
      {sname, "stdout"} => [message("app line")],
      {"deployex", "stdout"} => [message("deployex line")]
    })

    {:ok, view, _html} = live(conn, ~p"/logs/live")

    html = view |> element("#source-deployex") |> render_click()
    refute html =~ "deployex line"
    assert html =~ "app line"
    assert_received {:unsubscribed, "deployex", "stdout"}

    html = view |> element("#stream-stdout") |> render_click()
    refute html =~ "app line"

    html = view |> element("#stream-stdout") |> render_click()
    assert html =~ "app line"
  end

  @tag :capture_log
  test "source and stream in the query select them", %{conn: conn, sname: sname} do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)

    stub_logs(self(), %{
      {sname, "stderr"} => [message("only this")],
      {"deployex", "stderr"} => [message("not this")]
    })

    {:ok, _view, html} = live(conn, ~p"/logs/live?source=#{sname}&stream=stderr")

    assert html =~ "only this"
    refute html =~ "not this"
    assert html =~ "1 line · 1 of 3 sources"
  end

  @tag :capture_log
  test "a source the log server does not tail is not offered and not read", %{
    conn: conn,
    sname: sname
  } do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("app line")]}, ["deployex"])

    {:ok, _view, html} = live(conn, ~p"/logs/live")

    assert html =~ "app line"
    assert html =~ " of 2 sources"
    refute html =~ ~s(id="source-deployex")
    refute_received {:read, "deployex", _type, _minutes}
    refute_received {:subscribed, "deployex", _type}
  end

  @tag :capture_log
  test "the events source shows this host's events and follows new ones", %{
    conn: conn,
    sname: sname
  } do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("app line")]})

    Foundation.Notifications.notify("crash_restart", %{
      sname: "events-test-abc",
      crash_restart_count: 2
    })

    Process.sleep(50)

    {:ok, view, html} = live(conn, ~p"/logs/live?source=events")

    assert html =~ "events-test-abc crash restart · 2 crash restarts"
    refute html =~ "app line"
    refute_received {:read, ^sname, _type, _minutes}

    recent = %Foundation.Notifications.Recent{
      id: 1,
      at: DateTime.utc_now(),
      event: "deployment_started",
      payload: %{sname: "events-test-def", version: "1.2.3"}
    }

    send(view.pid, {:recent_notification, recent})
    assert render(view) =~ "deployment_started events-test-def 1.2.3"

    # Paused, the event waits for Resume
    view |> element("#logs-pause") |> render_click()
    send(view.pid, {:recent_notification, %{recent | payload: %{sname: "events-test-ghi"}}})
    refute render(view) =~ "events-test-ghi"
    assert view |> element("#logs-pause") |> render_click() =~ "events-test-ghi"

    # With the source off, a new event does not show
    view |> element("#source-events") |> render_click()
    send(view.pid, {:recent_notification, %{recent | payload: %{sname: "events-test-jkl"}}})
    refute render(view) =~ "events-test-jkl"
  end

  @tag :capture_log
  test "History reads the chosen range of the stored sources", %{conn: conn, sname: sname} do
    stub(Sentinel.LogsMock, :list_active_snames, fn -> [sname, "deployex"] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("old line", 3_000)]})

    {:ok, view, html} = live(conn, ~p"/logs/history")

    assert html =~ "old line"
    assert_received {:read, ^sname, "stdout", 30}
    refute_received {:subscribed, _, _}

    view |> element("#range-1h") |> render_click()
    assert_received {:read, ^sname, "stdout", 60}
  end

  @tag :capture_log
  test "the mode switch moves between Live and History", %{conn: conn, sname: sname} do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub(Sentinel.LogsMock, :list_active_snames, fn -> [] end)
    stub_logs(self(), %{})

    {:ok, view, _html} = live(conn, ~p"/logs/live")

    view |> element("#logs-history") |> render_click()
    assert_patch(view, ~p"/logs/history")
    assert render(view) =~ ~s(id="range-30m")
    assert_received {:unsubscribed, _sname, _type}

    view |> element("#logs-live") |> render_click()
    assert_patch(view, ~p"/logs/live")
  end
end
