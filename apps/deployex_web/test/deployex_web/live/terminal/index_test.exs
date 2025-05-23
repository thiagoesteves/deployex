defmodule DeployexWeb.Terminal.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import Mock

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias Host.Fixture.Terminal, as: FixtureTerminal

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /applications check buttom", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live
           |> element("a", "Host Terminal")
           |> render_click()
  end

  test "GET /terminal", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, test_pid_process, os_pid} end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, _index_live, _html} = live(conn, ~p"/terminal")

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Send Character to Terminal server", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    message = "Opening Host Terminal"

    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, test_pid_process, os_pid} end)
    |> expect(:send, fn ^os_pid, ^message ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)
    |> expect(:stop, fn ^os_pid -> :ok end)

    with_mock Foundation.Common, random_number: fn _from, _to -> 1 end do
      {:ok, index_live, _html} = live(conn, ~p"/terminal")

      # NOTE: Force handle_event in the live component
      index_live
      |> element("#host-shell-1")
      |> render_hook("key", %{"key" => message})

      FixtureTerminal.terminate_all()

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end
  end

  test "Send Character to Terminal Index Liveview from erlexec", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    message = "Sending from Host Terminal"

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      send(self(), {:stdout, os_pid, message})
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)

      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid -> :ok end)

    {:ok, _index_live, _html} = live(conn, ~p"/terminal")

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Terminal server timed out", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, _index_live, _html} = live(conn, ~p"/terminal")

    assert [pid] = FixtureTerminal.list_children()

    send(pid, :session_timeout)

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end
end
