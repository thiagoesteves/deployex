defmodule DeployexWeb.ShellTest do
  use ExUnit.Case, async: false

  import Mox

  alias DeployexWeb.Shell
  alias DeployexWeb.Shell.Session
  alias Foundation.Catalog

  setup :set_mox_global
  setup :verify_on_exit!

  @os_pid 4242

  setup do
    %{user: "user-#{System.unique_integer([:positive])}"}
  end

  # The terminal server runs the command through the mock, then the test plays the shell
  defp stub_shell(test_pid) do
    Host.CommanderMock
    |> stub(:run, fn
      "tmux kill-session" <> _ = command, [:sync] ->
        send(test_pid, {:cleanup, command})
        {:ok, []}

      commands, _options ->
        send(test_pid, {:started, commands})
        {:ok, self(), @os_pid}
    end)
    |> stub(:stop, fn @os_pid -> :ok end)
  end

  # Waits until the shell runs, so keys and sizes reach it
  defp wait_running(user, target \\ Shell.host()) do
    [{pid, _session}] = Registry.lookup(DeployexWeb.Shell.Registry, {user, target})
    assert eventually(fn -> is_integer(:sys.get_state(pid).os_pid) end)
  end

  # Closes the session and waits for its cleanup, while the mocks still answer
  defp close_and_wait(user, target \\ Shell.host()) do
    [{pid, _session}] = Registry.lookup(DeployexWeb.Shell.Registry, {user, target})
    %{terminal: terminal} = :sys.get_state(pid)
    refs = [Process.monitor(pid), Process.monitor(terminal)]
    Shell.close(user, target)

    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _pid, _reason})
    assert_receive {:cleanup, _command}
  end

  defp shell_output(user, target, data) do
    [{pid, _session}] = Registry.lookup(DeployexWeb.Shell.Registry, {user, target})
    %{terminal: terminal} = :sys.get_state(pid)
    send(terminal, {:stdout, @os_pid, data})
  end

  test "opens one host shell for each user and keeps it across pages", %{user: user} do
    stub_shell(self())

    assert {:ok,
            %Session{id: id, kind: :host_shell, target: "host", command: "tmux on host" <> _} =
              session} =
             Shell.open(user, Shell.host())

    assert_receive {:started, commands}
    assert commands =~ "tmux new-session -s DeployEx-#{id} -d"
    assert DateTime.diff(session.expires_at, session.started_at) == 15 * 60

    # A second page gets the same session, another user gets none
    assert {:ok, %Session{id: ^id}} = Shell.open(user, Shell.host())
    assert [%Session{id: ^id}] = Shell.list(user)
    assert Shell.list("someone-else") == []

    close_and_wait(user)
  end

  test "streams output to attached pages and replays it to a page that attaches later", %{
    user: user
  } do
    stub_shell(self())
    {:ok, %Session{id: id}} = Shell.open(user, Shell.host())
    assert_receive {:started, _commands}

    assert {:ok, %Session{id: ^id}, ""} = Shell.attach(user, Shell.host())

    shell_output(user, Shell.host(), "$ ")
    assert_receive {:shell_output, ^id, "$ "}

    shell_output(user, Shell.host(), "ls\r\n")
    assert_receive {:shell_output, ^id, "ls\r\n"}

    assert {:ok, %Session{} = session, "$ ls\r\n"} = Shell.attach(user, Shell.host())

    :ok = Shell.detach(session)
    shell_output(user, Shell.host(), "more")
    refute_receive {:shell_output, ^id, "more"}, 100

    close_and_wait(user)
  end

  test "sends keys and the terminal size to the shell once it runs", %{user: user} do
    test_pid = self()
    stub_shell(test_pid)

    Host.CommanderMock
    |> expect(:send, fn @os_pid, "ls\r" ->
      send(test_pid, :keys)
      :ok
    end)
    |> expect(:winsz, fn @os_pid, 30, 100 ->
      send(test_pid, :winsz)
      :ok
    end)

    {:ok, _session} = Shell.open(user, Shell.host())
    assert_receive {:started, _commands}
    wait_running(user)

    Shell.send_keys(user, Shell.host(), "ls\r")
    Shell.resize(user, Shell.host(), 30, 100)

    assert_receive :keys
    assert_receive :winsz

    close_and_wait(user)
  end

  test "ends the session when the shell exits, and tells the pages", %{user: user} do
    stub_shell(self())
    {:ok, %Session{id: id}} = Shell.open(user, Shell.host())
    assert_receive {:started, _commands}
    {:ok, _session, _scrollback} = Shell.attach(user, Shell.host())

    [{pid, _session}] = Registry.lookup(DeployexWeb.Shell.Registry, {user, Shell.host()})
    %{terminal: terminal} = :sys.get_state(pid)
    ref = Process.monitor(pid)
    send(terminal, {:DOWN, @os_pid, :process, self(), :normal})

    assert_receive {:shell_closed, ^id}
    assert_receive {:cleanup, _command}
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    assert eventually(fn -> Shell.list(user) == [] end)
  end

  test "keeps only the last 64 KB of output", %{user: user} do
    stub_shell(self())
    {:ok, _session} = Shell.open(user, Shell.host())
    assert_receive {:started, _commands}
    {:ok, _session, _scrollback} = Shell.attach(user, Shell.host())

    shell_output(user, Shell.host(), "é" <> String.duplicate("a", 65_535))
    shell_output(user, Shell.host(), "tail")
    assert_receive {:shell_output, _id, "tail"}

    {:ok, _session, scrollback} = Shell.attach(user, Shell.host())
    assert String.valid?(scrollback)
    assert byte_size(scrollback) <= 65_536
    assert String.ends_with?(scrollback, "tail")

    close_and_wait(user)
  end

  test "refuses a target that is not an instance", %{user: user} do
    assert {:error, :unknown_target} = Shell.open(user, "nothing-here")
  end

  test "refuses an instance with no release on the host", %{user: user} do
    sname = Catalog.create_sname("myelixir")
    assert {:error, :binary_not_found} = Shell.open(user, sname)
  end

  test "ignores actions on a session that does not exist", %{user: user} do
    assert :ok = Shell.send_keys(user, Shell.host(), "ls")
    assert :ok = Shell.resize(user, Shell.host(), 10, 10)
    assert :ok = Shell.close(user, Shell.host())
    assert :error = Shell.attach(user, Shell.host())
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end
end
