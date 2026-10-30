defmodule DeployexWeb.Logs.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mock
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
  test "Live opens on DeployEx and its events, and an app shows once it is selected", %{
    conn: conn,
    sname: sname
  } do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)

    stub_logs(self(), %{
      {sname, "stdout"} => [message("GET / [info] Sent 200\nsecond line")],
      {"deployex", "stderr"} => [message("[error] boom", 10)]
    })

    {:ok, view, html} = live(conn, ~p"/logs/live")

    assert html =~ "Streaming"
    assert html =~ "[error] boom"
    assert html =~ "Host time #{DeployexWeb.HostTime.zone()}"
    refute html =~ "GET / [info] Sent 200"
    assert html =~ "2 of 3 sources"
    assert has_element?(view, "#chip-events")
    assert has_element?(view, "#chip-deployex")
    refute_received {:read, ^sname, _type, _minutes}

    html = view |> element("#pick-app-myelixir") |> render_click()
    assert html =~ "GET / [info] Sent 200"
    assert html =~ "second line"
    assert has_element?(view, "#chip-#{sname}")
    assert_received {:read, ^sname, "stdout", 5}
    assert_received {:subscribed, ^sname, "stderr"}

    # New lines wait for the next flush, then show together
    send(view.pid, {:logs_new_data, sname, "stdout", message("a new line", 0)})
    send(view.pid, {:logs_new_data, sname, "stderr", message("and another", 0)})
    refute render(view) =~ "a new line"
    send(view.pid, :flush_lines)
    html = render(view)
    assert html =~ "a new line"
    assert html =~ "and another"

    html = view |> element("#chip-#{sname} button") |> render_click()
    refute html =~ "GET / [info] Sent 200"
    assert_received {:unsubscribed, ^sname, "stdout"}
  end

  @tag :capture_log
  test "an app of several instances is picked whole or by instance, and every app at once", %{
    conn: conn,
    sname: sname
  } do
    second = Catalog.create_sname("myelixir")
    other = Catalog.create_sname("myerlang")
    stub(Deployer.MonitorMock, :list, fn -> [sname, second, other] end)
    stub_logs(self(), %{})

    {:ok, view, _html} = live(conn, ~p"/logs/live")

    view |> element("#pick-#{sname}") |> render_click()
    assert has_element?(view, ~s(#pick-app-myelixir[aria-pressed="mixed"]))
    assert has_element?(view, "#chip-#{sname}")

    html = view |> element("#pick-app-myelixir") |> render_click()
    assert has_element?(view, ~s(#pick-app-myelixir[aria-pressed="true"]))
    assert html =~ "myelixir · 2 instances"
    refute has_element?(view, "#chip-#{sname}")

    html = view |> element("#pick-every-app") |> render_click()
    assert html =~ "Remove every app"
    assert has_element?(view, "#chip-#{other}")
    assert_received {:subscribed, ^other, "stdout"}

    html = view |> element("#pick-every-app") |> render_click()
    assert html =~ "Add every app (3 instances)"
    refute has_element?(view, "#chip-app-myelixir")
    assert has_element?(view, "#chip-deployex")

    view |> element("#pick-app-myelixir") |> render_click()
    view |> element("#chip-app-myelixir button") |> render_click()
    assert has_element?(view, ~s(#pick-app-myelixir[aria-pressed="false"]))
  end

  @tag :capture_log
  test "Pause keeps the new lines for Resume, and Clear empties the view", %{
    conn: conn,
    sname: sname
  } do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("stored line")]})

    {:ok, view, _html} = live(conn, ~p"/logs/live?source=#{sname}")

    html = view |> element("#logs-pause") |> render_click()
    assert html =~ "Paused"

    send(view.pid, {:logs_new_data, sname, "stdout", message("during the pause", 0)})
    send(view.pid, :flush_lines)
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

    {:ok, view, _html} = live(conn, ~p"/logs/live?source=#{sname}")

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

    {:ok, view, _html} = live(conn, ~p"/logs/live?#{%{source: "#{sname},deployex"}}")

    html = view |> element("#chip-deployex button") |> render_click()
    refute html =~ "deployex line"
    assert html =~ "app line"
    assert_received {:unsubscribed, "deployex", "stdout"}

    # A line that was already on its way from the source turned off does not show
    send(view.pid, {:logs_new_data, "deployex", "stdout", message("late line", 0)})
    send(view.pid, :flush_lines)
    refute render(view) =~ "late line"

    html = view |> element("#pick-deployex") |> render_click()
    assert html =~ "deployex line"

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
    assert html =~ "1 line · 1 of 3 sources · stderr only"
  end

  @tag :capture_log
  test "a source the log server does not tail is not offered and not read", %{
    conn: conn,
    sname: sname
  } do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("app line")]}, ["deployex"])

    {:ok, _view, html} = live(conn, ~p"/logs/live?#{%{source: "#{sname},deployex"}}")

    assert html =~ "app line"
    assert html =~ " of 2 sources"
    refute html =~ ~s(id="pick-deployex")
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
    send(view.pid, :flush_lines)
    assert render(view) =~ "deployment_started events-test-def 1.2.3"

    # Paused, the event waits for Resume
    view |> element("#logs-pause") |> render_click()
    send(view.pid, {:recent_notification, %{recent | payload: %{sname: "events-test-ghi"}}})
    send(view.pid, :flush_lines)
    refute render(view) =~ "events-test-ghi"
    assert view |> element("#logs-pause") |> render_click() =~ "events-test-ghi"

    # With the source off, a new event does not show
    view |> element("#chip-events button") |> render_click()
    send(view.pid, {:recent_notification, %{recent | payload: %{sname: "events-test-jkl"}}})
    send(view.pid, :flush_lines)
    refute render(view) =~ "events-test-jkl"
  end

  @tag :capture_log
  test "an event older than the read window shows in History, not in Live", %{conn: conn} do
    stub(Deployer.MonitorMock, :list, fn -> [] end)
    stub(Sentinel.LogsMock, :list_active_snames, fn -> [] end)
    stub_logs(self(), %{})
    two_hours_ago = DateTime.add(DateTime.utc_now(:second), -2 * 3_600)

    with_mock DateTime, [:passthrough], utc_now: fn :second -> two_hours_ago end do
      Foundation.Notifications.notify("crash_restart", %{sname: "events-test-old"})
      Process.sleep(50)
    end

    # The bell lists it too, so only the log lines are read
    {:ok, view, _html} = live(conn, ~p"/logs/live?source=events")
    refute has_element?(view, "#logs-lines", "events-test-old")

    {:ok, view, _html} = live(conn, ~p"/logs/history?source=events")
    refute has_element?(view, "#logs-lines", "events-test-old")
    view |> element("#range-6h") |> render_click()
    assert has_element?(view, "#logs-lines", "events-test-old")
  end

  @tag :capture_log
  test "History reads the chosen range of the stored sources", %{conn: conn, sname: sname} do
    stub(Sentinel.LogsMock, :list_active_snames, fn -> [sname, "deployex"] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("old line", 3_000)]})

    {:ok, view, html} = live(conn, ~p"/logs/history?source=#{sname}")

    assert html =~ "old line"
    assert_received {:read, ^sname, "stdout", 30}
    refute_received {:subscribed, _, _}

    view |> element("#range-1h") |> render_click()
    assert_received {:read, ^sname, "stdout", 60}
  end

  @tag :capture_log
  test "since picks the shortest History range that covers that time", %{conn: conn, sname: sname} do
    stub(Sentinel.LogsMock, :list_active_snames, fn -> [sname] end)
    stub_logs(self(), %{})

    two_hours_ago = System.os_time(:second) - 2 * 3_600
    {:ok, _view, html} = live(conn, ~p"/logs/history?#{%{source: sname, since: two_hours_ago}}")

    assert_received {:read, ^sname, "stdout", 360}
    assert html =~ ~r/id="range-6h"[^>]*aria-pressed="true"/

    # A time past the longest range reads the longest, and a bad value keeps the default
    {:ok, _view, _html} = live(conn, ~p"/logs/history?#{%{source: sname, since: 0}}")
    assert_received {:read, ^sname, "stdout", 10_080}

    {:ok, _view, _html} = live(conn, ~p"/logs/history?#{%{source: sname, since: "yesterday"}}")
    assert_received {:read, ^sname, "stdout", 30}
  end

  @tag :capture_log
  test "the filter in the URL sets the text filter", %{conn: conn, sname: sname} do
    stub(Sentinel.LogsMock, :list_active_snames, fn -> [sname] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("keep this"), message("drop that")]})

    {:ok, _view, html} = live(conn, ~p"/logs/history?#{%{source: sname, filter: "keep"}}")
    assert html =~ ~s(value="keep")
    assert html =~ "this"
    refute html =~ "drop that"
  end

  @tag :capture_log
  test "a comma list of sources selects the known ones", %{conn: conn, sname: sname} do
    stub(Sentinel.LogsMock, :list_active_snames, fn -> [sname, "deployex"] end)
    stub_logs(self(), %{})

    {:ok, view, _html} = live(conn, ~p"/logs/history?#{%{source: "events,#{sname},unknown"}}")

    assert has_element?(view, ~s(#pick-events[aria-pressed="true"]))
    assert has_element?(view, ~s(#pick-app-myelixir[aria-pressed="true"]))
    assert has_element?(view, ~s(#pick-deployex[aria-pressed="false"]))
    assert_received {:read, ^sname, "stdout", 30}
    refute_received {:read, "deployex", _type, _range}
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

  # The href of an export link, as the query params it holds
  defp export_query(view, id) do
    [_all, query] = Regex.run(~r/href="[^"?]+\?([^"]+)"/, view |> element(id) |> render())
    query |> String.replace("&amp;", "&") |> URI.decode_query()
  end

  @tag :capture_log
  test "Copy takes the lines shown and Export the selection", %{conn: conn, sname: sname} do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub(Sentinel.LogsMock, :list_active_snames, fn -> [sname] end)
    stub_logs(self(), %{{sname, "stdout"} => [message("stored line")]})

    {:ok, view, _html} = live(conn, ~p"/logs/live?#{%{source: sname, stream: "stdout"}}")

    assert view |> element("#logs-copy") |> render() =~ "logs-lines"
    refute has_element?(view, "#logs-copy[disabled]")

    # Live exports from 5 minutes before the page opened
    query = export_query(view, "#logs-export-jsonl")
    assert %{"source" => ^sname, "stream" => "stdout", "format" => "jsonl"} = query
    assert_in_delta String.to_integer(query["since"]), System.os_time(:second) - 300, 5
    assert export_query(view, "#logs-export-log")["format"] == "log"

    view |> element("#logs-filter") |> render_change(%{"filter" => "zzz"})
    assert has_element?(view, "#logs-copy[disabled]")
    assert export_query(view, "#logs-export-log")["filter"] == "zzz"

    # After Clear it exports from the time of Clear
    view |> element("#logs-clear") |> render_click()

    assert_in_delta String.to_integer(export_query(view, "#logs-export-log")["since"]),
                    System.os_time(:second),
                    5

    {:ok, view, _html} = live(conn, ~p"/logs/history?#{%{source: sname}}")
    view |> element("#range-6h") |> render_click()
    query = export_query(view, "#logs-export-log")
    assert %{"minutes" => "360", "stream" => "stdout,stderr"} = query
    refute Map.has_key?(query, "since")
  end
end
