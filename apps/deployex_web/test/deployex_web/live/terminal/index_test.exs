defmodule DeployexWeb.Terminal.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias DeployexWeb.Shell

  setup [:set_mox_global, :verify_on_exit!, :log_in_default_user]

  @os_pid 5151

  setup do
    test_pid = self()

    Host.CommanderMock
    |> stub(:run, fn
      "tmux kill-session" <> _ = command, [:sync] ->
        send(test_pid, {:cleanup, command})
        {:ok, []}

      _commands, _options ->
        {:ok, self(), @os_pid}
    end)
    |> stub(:stop, fn @os_pid -> :ok end)

    stub(Deployer.MonitorMock, :list, fn -> [] end)

    :ok
  end

  # Ends the user's sessions and waits for them and their terminals, while the mocks still answer
  defp close_all(user) do
    for session <- Shell.list(user) do
      [{pid, _}] = Registry.lookup(DeployexWeb.Shell.Registry, {user, session.target})
      %{terminal: terminal} = :sys.get_state(pid)
      refs = [Process.monitor(pid), Process.monitor(terminal)]
      Shell.close(user, session.target)
      for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _pid, _reason})
    end
  end

  # Waits until the shell runs, so keys reach it
  defp wait_running(user, target) do
    [{pid, _}] = Registry.lookup(DeployexWeb.Shell.Registry, {user, target})

    Enum.reduce_while(1..50, nil, fn _, _ ->
      if is_integer(:sys.get_state(pid).os_pid),
        do: {:halt, :ok},
        else: Process.sleep(10) && {:cont, nil}
    end)
  end

  @tag :capture_log
  test "GET /terminal with no session offers the host shell and DeployEx", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/terminal")

    assert html =~ "No open session"
    assert html =~ "Open an IEx shell on an instance, or a shell on this host, with New session."
    assert html =~ ~s(id="new-host")
    assert html =~ "Host shell"
    assert html =~ ~s(id="new-deployex")
  end

  @tag :capture_log
  test "a new host shell gets a tab, the header and the shortcuts, and Disconnect ends it", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/terminal")

    view |> element("#new-host") |> render_click()
    assert_patch(view, ~p"/terminal?target=host")

    html = render(view)
    assert html =~ "tmux on host · user"
    assert html =~ "Session closes in"
    assert html =~ "tmux keys"
    assert html =~ "This shell runs as the deployex user."
    assert html =~ "Every session is open." or html =~ ~s(id="new-deployex")
    refute html =~ ~s(id="new-host")
    assert [%{target: "host"}] = Shell.list(user.username)

    html = view |> element("#terminal-shortcuts") |> render_click()
    refute html =~ "tmux keys"

    view |> element("#terminal-disconnect") |> render_click()
    assert_receive {:cleanup, "tmux kill-session" <> _}
    assert_patch(view, ~p"/terminal")
    assert render(view) =~ "No open session"
  end

  @tag :capture_log
  test "the page shows the shell output, and sends keys and the size", %{conn: conn, user: user} do
    test_pid = self()

    Host.CommanderMock
    |> expect(:send, fn @os_pid, "ls\r" ->
      send(test_pid, :keys)
      :ok
    end)
    |> expect(:winsz, fn @os_pid, 30, 100 ->
      send(test_pid, :winsz)
      :ok
    end)

    {:ok, _session} = Shell.open(user.username, "host")
    wait_running(user.username, "host")

    {:ok, view, _html} = live(conn, ~p"/terminal?target=host")
    assert_push_event(view, "shell-reset-host", %{data: ""})

    [{pid, _}] = Registry.lookup(DeployexWeb.Shell.Registry, {user.username, "host"})
    send(:sys.get_state(pid).terminal, {:stdout, @os_pid, "$ "})
    assert_push_event(view, "shell-output-host", %{data: "$ "})

    xterm = element(view, "[phx-hook=XTerm]")
    render_hook(xterm, "shell-keys", %{"target" => "host", "keys" => "ls\r"})
    render_hook(xterm, "shell-resize", %{"target" => "host", "rows" => 30, "cols" => 100})

    assert_receive :keys
    assert_receive :winsz
    close_all(user.username)
  end

  @tag :capture_log
  test "a session opened elsewhere shows as a tab, and another tab can be selected", %{
    conn: conn,
    user: user
  } do
    {:ok, _session} = Shell.open(user.username, "host")

    {:ok, view, html} = live(conn, ~p"/terminal")
    assert html =~ "tmux on host"

    view |> element("button[phx-value-target=host].dx-tab-sel") |> render_click()
    assert_patch(view, ~p"/terminal?target=host")
    close_all(user.username)
  end

  @tag :capture_log
  test "a shell that cannot start shows an error", %{conn: conn} do
    stub(Deployer.MonitorMock, :list, fn -> ["myelixir-nobinary"] end)

    {:ok, view, _html} = live(conn, ~p"/terminal")

    html = view |> element("#new-myelixir-nobinary") |> render_click()
    assert html =~ "Could not open a shell on myelixir-nobinary"
  end

  @tag :capture_log
  test "two sessions show side by side, each with its output, and swap or close back to one", %{
    conn: conn,
    user: user
  } do
    {:ok, _session} = Shell.open(user.username, "host")
    wait_running(user.username, "host")

    {:ok, view, _html} = live(conn, ~p"/terminal?target=host")
    assert_push_event(view, "shell-reset-host", %{data: ""})
    refute has_element?(view, "#terminal-unsplit")

    # Split opens a picker at once, and a pick opens its session there, with nothing open before
    html = view |> element("#terminal-split") |> render_click()
    assert html =~ "Show beside"
    assert has_element?(view, "#pick-deployex", "DeployEx")
    refute has_element?(view, "#pick-host")

    view |> element("#pick-deployex") |> render_click()
    assert_patch(view, "/terminal?split=deployex&target=host")
    assert_push_event(view, "shell-reset-deployex", %{data: ""})
    wait_running(user.username, "deployex")
    assert has_element?(view, "#terminal-unsplit")
    assert [_host, _deployex] = view |> render() |> then(&Regex.scan(~r/phx-hook="XTerm"/, &1))

    # Each session's output goes to its own pane
    for {target, data} <- [{"host", "$ "}, {"deployex", "iex> "}] do
      [{pid, _}] = Registry.lookup(DeployexWeb.Shell.Registry, {user.username, target})
      send(:sys.get_state(pid).terminal, {:stdout, @os_pid, data})
    end

    assert_push_event(view, "shell-output-host", %{data: "$ "})
    assert_push_event(view, "shell-output-deployex", %{data: "iex> "})

    # The second session's tab swaps the panes
    view |> element("button[phx-value-target=deployex].dx-tab-sel") |> render_click()
    assert_patch(view, "/terminal?split=host&target=deployex")

    # Closing the second pane keeps its session running
    view |> element("#terminal-unsplit") |> render_click()
    assert_patch(view, "/terminal?target=deployex")
    assert [_host, _deployex] = Shell.list(user.username)

    close_all(user.username)
  end
end
