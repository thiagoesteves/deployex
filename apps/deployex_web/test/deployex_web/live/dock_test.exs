defmodule DeployexWeb.DockTest do
  use DeployexWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias DeployexWeb.Shell
  alias Foundation.Catalog
  alias Sentinel.Logs.Message

  setup [:set_mox_global, :verify_on_exit!, :log_in_default_user]

  @os_pid 6161

  setup do
    test_pid = self()

    Host.CommanderMock
    |> stub(:run, fn
      "tmux kill-session" <> _, [:sync] -> {:ok, []}
      _commands, _options -> {:ok, self(), @os_pid}
    end)
    |> stub(:stop, fn @os_pid -> :ok end)

    Sentinel.LogsMock
    |> stub(:get_types_by_sname, fn _sname -> ["stdout", "stderr"] end)
    |> stub(:subscribe_for_new_logs, fn sname, type ->
      send(test_pid, {:subscribed, sname, type})
      :ok
    end)
    |> stub(:unsubscribe_for_new_logs, fn sname, type ->
      send(test_pid, {:unsubscribed, sname, type})
      :ok
    end)

    stub(Deployer.MonitorMock, :list, fn -> [] end)

    %{sname: Catalog.create_sname("myelixir")}
  end

  defp dock(conn) do
    {:ok, view, _html} = live(conn, ~p"/documentation")
    {view, find_live_child(view, "dock-live")}
  end

  defp message(log), do: %Message{timestamp: System.os_time(:millisecond) - 1_000, log: log}

  @tag :capture_log
  test "a logs tab shows the last lines of an instance, then follows it", %{
    conn: conn,
    sname: sname
  } do
    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn
      ^sname, "stdout", [from: 30, order: :asc] -> [message("booted")]
      ^sname, "stderr", _options -> [message("[error] failed once")]
    end)

    {_view, dock} = dock(conn)
    refute render(dock) =~ "dx-dock-bar"

    html = render_hook(dock, "open", %{"kind" => "logs", "target" => sname, "app" => "myelixir"})

    assert html =~ "#{sname} · last 30 minutes, then live"
    assert html =~ "booted"
    assert html =~ "[error] failed once"
    assert html =~ "Open in Logs"
    assert_received {:subscribed, ^sname, "stdout"}

    send(dock.pid, {:logs_new_data, sname, "stdout", message("a new line")})
    assert render(dock) =~ "a new line"

    # The filter keeps the lines that hold its text, also as they come
    html = dock |> element("#dock-filter") |> render_change(%{"filter" => "NEW"})
    assert html =~ "a new line"
    refute html =~ "failed once"

    send(dock.pid, {:logs_new_data, sname, "stdout", message("another one")})
    refute render(dock) =~ "another one"

    html = dock |> element("#dock-filter") |> render_change(%{"filter" => "zzz"})
    assert html =~ "No line holds zzz. Open in Logs reads the history too."

    # Open in Logs closes the tab, then opens Live Logs with its instance and filter
    assert html =~ "/logs/live?filter=zzz&amp;source=#{sname}"

    html = dock |> element("#dock-filter") |> render_change(%{"filter" => ""})
    assert html =~ "failed once"

    html = dock |> element("#dock-stream-stderr") |> render_click()
    refute html =~ "failed once"

    html = dock |> element("#dock-stream-stdout") |> render_click()
    assert html =~ "No lines for these streams."

    # Opening it again focuses the same tab
    render_hook(dock, "open", %{"kind" => "logs", "target" => sname, "app" => "myelixir"})
    assert [_tab] = Regex.scan(~r/id="dock-tab-/, render(dock))

    html = dock |> element("#dock-close-logs\\:#{sname}") |> render_click()
    refute html =~ "dx-dock-bar"
    assert_received {:unsubscribed, ^sname, "stdout"}
  end

  @tag :capture_log
  test "an app's logs tab follows every instance of the app", %{conn: conn, sname: sname} do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, _options -> [] end)

    {_view, dock} = dock(conn)

    html =
      render_hook(dock, "open", %{"kind" => "logs", "target" => "myelixir", "app" => "myelixir"})

    assert html =~ "every instance of myelixir"
    assert html =~ "No lines for these streams."

    send(dock.pid, {:logs_new_data, sname, "stderr", message("from the app")})
    assert render(dock) =~ "from the app"
    assert render(dock) =~ sname
  end

  @tag :capture_log
  test "a shell tab opens the user's session and asks before the dock closes it", %{
    conn: conn,
    user: user
  } do
    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, _options -> [] end)

    {_view, dock} = dock(conn)

    html =
      render_hook(dock, "open", %{"kind" => "shell", "target" => "deployex", "app" => "deployex"})

    assert html =~ "Closes in"
    assert html =~ "dx-dtab-term"
    assert [%{target: "deployex"}] = Shell.list(user.username)
    assert_push_event(dock, "shell-reset-deployex", %{data: ""})

    # The shortcuts of the remote IEx shell open next to it, and close again
    refute html =~ "IEx shortcuts"
    html = dock |> element("#dock-shortcuts") |> render_click()
    assert html =~ "IEx shortcuts"
    assert html =~ "runtime_info"
    assert html =~ "A release has no Mix, sources or docs"
    refute html =~ "#iex:break"
    refute dock |> element("#dock-shortcuts") |> render_click() =~ "IEx shortcuts"

    # A logs tab next to it, then back to the shell
    render_hook(dock, "open", %{"kind" => "logs", "target" => "deployex", "app" => "deployex"})
    dock |> element("#dock-tab-shell\\:deployex") |> render_click()

    html = dock |> element("#dock-close") |> render_click()
    assert html =~ "Close the dock?"
    assert html =~ "It ends 1 shell session"

    html = dock |> element("button", "Cancel") |> render_click()
    refute html =~ "Close the dock?"

    [{pid, _}] = Registry.lookup(DeployexWeb.Shell.Registry, {user.username, "deployex"})
    %{terminal: terminal} = :sys.get_state(pid)
    refs = [Process.monitor(pid), Process.monitor(terminal)]

    dock |> element("#dock-close") |> render_click()
    html = dock |> element("#dock-close-confirm") |> render_click()
    refute html =~ "dx-dock-bar"

    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _pid, _reason})
    assert Shell.list(user.username) == []
  end

  @tag :capture_log
  test "a dock with only logs closes at once", %{conn: conn, sname: sname} do
    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, _options -> [] end)

    {_view, dock} = dock(conn)
    render_hook(dock, "open", %{"kind" => "logs", "target" => sname, "app" => "myelixir"})

    html = dock |> element("#dock-close") |> render_click()
    refute html =~ "Close the dock?"
    refute html =~ "dx-dock-bar"
  end

  @tag :capture_log
  test "a shell that cannot start shows no tab", %{conn: conn} do
    {_view, dock} = dock(conn)

    html =
      render_hook(dock, "open", %{
        "kind" => "shell",
        "target" => "myelixir-nobinary",
        "app" => "myelixir"
      })

    refute html =~ "dx-dock-bar"
  end

  @tag :capture_log
  test "a shell and a logs tab show side by side, swap, and close back to one pane", %{
    conn: conn,
    user: user
  } do
    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, _options ->
      [message("a log line")]
    end)

    {_view, dock} = dock(conn)
    render_hook(dock, "open", %{"kind" => "logs", "target" => "deployex", "app" => "deployex"})
    render_hook(dock, "open", %{"kind" => "shell", "target" => "deployex", "app" => "deployex"})
    refute has_element?(dock, "#dock-unsplit")

    # Two logs tabs cannot show together, a logs tab and a shell can
    html = dock |> element("#dock-split-logs\\:deployex") |> render_click()
    assert has_element?(dock, "#dock-unsplit")
    assert html =~ "a log line"
    assert html =~ ~s(phx-hook="XTerm")
    assert {shell, _} = :binary.match(html, "dock-xterm-")
    assert {logs, _} = :binary.match(html, ~s(id="dock-log"))
    assert shell < logs

    # The second pane's tab swaps the panes
    html = dock |> element("#dock-tab-logs\\:deployex") |> render_click()
    assert {shell, _} = :binary.match(html, "dock-xterm-")
    assert {logs, _} = :binary.match(html, ~s(id="dock-log"))
    assert logs < shell

    # Closing the second pane keeps its tab, and the shell keeps running
    html = dock |> element("#dock-unsplit") |> render_click()
    refute html =~ ~s(phx-hook="XTerm")
    assert html =~ "dock-tab-shell:deployex"
    assert [%{target: "deployex"}] = Shell.list(user.username)

    # Closing the first pane's tab while split leaves the second one alone
    dock |> element("#dock-split-shell\\:deployex") |> render_click()
    html = dock |> element("#dock-close-logs\\:deployex") |> render_click()
    refute html =~ ~s(id="dock-log")
    refute has_element?(dock, "#dock-unsplit")
    assert html =~ ~s(phx-hook="XTerm")

    [{pid, _}] = Registry.lookup(DeployexWeb.Shell.Registry, {user.username, "deployex"})
    ref = Process.monitor(pid)
    dock |> element("#dock-close") |> render_click()
    dock |> element("#dock-close-confirm") |> render_click()
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}
  end
end
