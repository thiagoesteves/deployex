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
      ^sname, "stdout", [from: 30, order: :asc, limit: 500] -> [message("booted")]
      ^sname, "stderr", _options -> [message("[error] failed once")]
    end)

    {_view, dock} = dock(conn)
    refute render(dock) =~ "dx-dock-bar"

    html = render_hook(dock, "open", %{"kind" => "logs", "target" => sname, "app" => "myelixir"})

    assert html =~
             "#{sname} · last 30 minutes, then live · host time #{DeployexWeb.HostTime.zone()}"

    assert html =~ "booted"
    assert html =~ "[error] failed once"
    assert html =~ "Open in Logs"
    assert_received {:subscribed, ^sname, "stdout"}

    send(dock.pid, {:logs_new_data, sname, "stdout", message("a new line")})
    send(dock.pid, :flush_lines)
    assert render(dock) =~ "a new line"

    # The filter keeps the lines that hold its text, also as they come
    html = dock |> element("#dock-filter") |> render_change(%{"filter" => "NEW"})
    assert html =~ "a new line"
    refute html =~ "failed once"

    send(dock.pid, {:logs_new_data, sname, "stdout", message("another one")})
    send(dock.pid, :flush_lines)
    refute render(dock) =~ "another one"

    html = dock |> element("#dock-filter") |> render_change(%{"filter" => "zzz"})
    assert html =~ "No line holds zzz. Open in Logs reads the history too."

    # Open in Logs closes the tab, then opens Live Logs with its instance and filter
    assert html =~ "/logs/live?filter=zzz&amp;source=#{sname}"

    # Copy has no line to take, and Export reads from 30 minutes before the tab opened
    assert has_element?(dock, "#dock-logs-copy[disabled]")
    link = dock |> element("#dock-logs-export-log") |> render()

    assert link =~
             ~r/export\?source=#{sname}&amp;stream=stdout%2Cstderr&amp;since=\d+&amp;filter=zzz&amp;format=log"/

    [_all, since] = Regex.run(~r/since=(\d+)/, link)
    assert_in_delta String.to_integer(since), System.os_time(:second) - 30 * 60, 5

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
    send(dock.pid, :flush_lines)
    assert render(dock) =~ "from the app"
    assert render(dock) =~ sname
  end

  @tag :capture_log
  test "logs tabs that share an instance follow it once, until the last of them closes", %{
    conn: conn,
    sname: sname
  } do
    stub(Deployer.MonitorMock, :list, fn -> [sname] end)
    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, _options -> [] end)

    {_view, dock} = dock(conn)
    render_hook(dock, "open", %{"kind" => "logs", "target" => "myelixir", "app" => "myelixir"})
    render_hook(dock, "open", %{"kind" => "logs", "target" => sname, "app" => "myelixir"})

    assert_received {:subscribed, ^sname, "stdout"}
    refute_received {:subscribed, ^sname, "stdout"}

    dock |> element("#dock-close-logs\\:#{sname}") |> render_click()
    refute_received {:unsubscribed, ^sname, _type}

    # The app's tab still gets the instance's lines
    send(dock.pid, {:logs_new_data, sname, "stdout", message("still here")})
    send(dock.pid, :flush_lines)
    assert render(dock) =~ "still here"

    dock |> element("#dock-close-logs\\:myelixir") |> render_click()
    assert_received {:unsubscribed, ^sname, "stdout"}
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
    assert_push_event(dock, "shell-reset-dock-deployex", %{data: ""})

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
  test "Split offers what fits beside a tab, opens it there, and swaps or closes back", %{
    conn: conn,
    user: user
  } do
    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, _options ->
      [message("a log line")]
    end)

    {_view, dock} = dock(conn)
    render_hook(dock, "open", %{"kind" => "shell", "target" => "deployex", "app" => "deployex"})

    # Split opens a picker at once, with the shell's own logs, which need no tab yet
    html = dock |> element("#dock-split") |> render_click()
    assert html =~ "Show beside deployex"
    assert has_element?(dock, "#dock-pick-logs-deployex", "this instance")
    refute has_element?(dock, "#dock-pick-shell-deployex")

    html = dock |> element("#dock-pick-logs-deployex") |> render_click()
    assert html =~ "a log line"
    assert html =~ ~s(phx-hook="XTerm")
    # The second pane has its own stream of lines and controls
    assert html =~ ~s(id="dock-lines-2")
    assert html =~ ~s(id="dock-filter-2")
    assert {shell, _} = :binary.match(html, "dock-xterm-")
    assert {logs, _} = :binary.match(html, ~s(id="dock-log))
    assert shell < logs

    # The second pane's tab swaps the panes
    html = dock |> element("#dock-tab-logs\\:deployex") |> render_click()
    assert {shell, _} = :binary.match(html, "dock-xterm-")
    assert {logs, _} = :binary.match(html, ~s(id="dock-log))
    assert logs < shell

    # Closing the second pane keeps its tab, and the shell keeps running
    html = dock |> element("#dock-unsplit") |> render_click()
    refute html =~ ~s(phx-hook="XTerm")
    assert html =~ "dock-tab-shell:deployex"
    assert [%{target: "deployex"}] = Shell.list(user.username)

    # Beside a logs tab, the picker offers its shell, and no second copy of itself
    dock |> element("#dock-split") |> render_click()
    assert has_element?(dock, "#dock-pick-shell-deployex")
    refute has_element?(dock, "#dock-pick-logs-deployex")
    dock |> element("#dock-pick-shell-deployex") |> render_click()

    # Closing the first pane's tab while split leaves the second one alone
    html = dock |> element("#dock-close-logs\\:deployex") |> render_click()
    refute html =~ ~s(id="dock-log)
    refute has_element?(dock, "#dock-unsplit")
    assert html =~ ~s(phx-hook="XTerm")

    [{pid, _}] = Registry.lookup(DeployexWeb.Shell.Registry, {user.username, "deployex"})
    ref = Process.monitor(pid)
    dock |> element("#dock-close") |> render_click()
    dock |> element("#dock-close-confirm") |> render_click()
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}
  end

  @tag :capture_log
  test "a logs tab splits with a sibling's logs, and each pane follows its own instance", %{
    conn: conn,
    sname: sname
  } do
    sibling = Catalog.create_sname("myelixir")
    stub(Deployer.MonitorMock, :list, fn -> [String.to_atom(sname), String.to_atom(sibling)] end)

    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn
      ^sname, "stdout", _options -> [message("from the first")]
      ^sibling, "stdout", _options -> [message("from the sibling")]
      _sname, _type, _options -> []
    end)

    {_view, dock} = dock(conn)
    render_hook(dock, "open", %{"kind" => "logs", "target" => sname, "app" => "myelixir"})

    dock |> element("#dock-split") |> render_click()
    assert has_element?(dock, "#dock-pick-logs-#{sibling}", "another instance")
    assert has_element?(dock, "#dock-pick-shell-#{sname}", "this instance")
    # The logs of every instance hold this instance's lines too, so they are no pick beside it
    refute has_element?(dock, "#dock-pick-logs-myelixir")

    html = dock |> element("#dock-pick-logs-#{sibling}") |> render_click()
    assert html =~ "from the first"
    assert html =~ "from the sibling"

    # A new line goes to its instance's pane only
    send(dock.pid, {:logs_new_data, sibling, "stdout", message("sibling again")})
    send(dock.pid, :flush_lines)
    html = render(dock)
    [first, second] = String.split(html, ~s(id="dock-lines-2"))
    refute first =~ "sibling again"
    assert second =~ "sibling again"

    # Each pane filters its own tab
    html = dock |> element("#dock-filter-2") |> render_change(%{"filter" => "again"})
    assert html =~ "from the first"
    refute html =~ "from the sibling"
  end

  @tag :capture_log
  test "a shell opened next to a logs tab keeps both, as lines and output come", %{
    conn: conn,
    sname: sname,
    user: user
  } do
    stub(Sentinel.LogsMock, :list_data_by_sname_log_type, fn _sname, _type, _options ->
      [message("a log line")]
    end)

    {_view, dock} = dock(conn)
    render_hook(dock, "open", %{"kind" => "logs", "target" => sname, "app" => "myelixir"})
    render_hook(dock, "open", %{"kind" => "shell", "target" => "deployex", "app" => "deployex"})

    send(dock.pid, {:logs_new_data, sname, "stdout", message("while hidden")})
    send(dock.pid, :flush_lines)
    [{pid, _}] = Registry.lookup(DeployexWeb.Shell.Registry, {user.username, "deployex"})
    send(:sys.get_state(pid).terminal, {:stdout, @os_pid, "iex> "})

    render_hook(dock |> element("[phx-hook=XTerm]"), "shell-resize", %{
      "target" => "deployex",
      "rows" => 20,
      "cols" => 80
    })

    html = render(dock)
    assert html =~ "dock-tab-logs:#{sname}"
    assert html =~ "dock-tab-shell:deployex"

    html = dock |> element("#dock-tab-logs\\:#{sname}") |> render_click()
    assert html =~ "while hidden"

    ref = Process.monitor(pid)
    dock |> element("#dock-close") |> render_click()
    dock |> element("#dock-close-confirm") |> render_click()
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}
  end
end
