defmodule DeployexWeb.Applications.TerminalTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import Mox

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  alias Deployex.Fixture.Binary
  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus
  alias Deployex.Fixture.Terminal, as: FixtureTerminal
  alias DeployexWeb.ApplicationsLive.Terminal

  test "Access to terminal by instance", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    Binary.create_bin_files(1)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Access to terminal by instance - Gleam", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    app_lang = "gleam"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> app_lang end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    Binary.create_bin_files(app_lang, 1)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/testapp/1/current/erlang-shipment"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Access to terminal by instance - Erlang", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    app_lang = "erlang"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> app_lang end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    Binary.create_bin_files(app_lang, 1)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Invalid cookie", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, 1, fn _command, _options ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      {:error, :invalid_cookie}
    end)

    assert capture_log(fn ->
             {:ok, index_live, _html} = live(conn, ~p"/applications")

             Binary.create_bin_files(1)

             assert index_live |> element("#app-terminal-1") |> render_click() =~
                      "Terminal for testapp [1]"

             assert_receive {:handle_ref_event, ^ref}, 1_000
           end) =~
             "Error while trying to run the commands for instance: 1, reason: {:error, :invalid_cookie}"
  end

  test "Send Character to iex terminal", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    message = "Opening Terminal"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options -> {:ok, test_pid_process, os_pid} end)
    |> expect(:send, fn ^os_pid, ^message ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)
    |> expect(:stop, fn ^os_pid -> :ok end)

    Binary.create_bin_files(1)
    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"

    # NOTE: Force handle_event in the live component
    index_live
    |> element("#iex-1")
    |> render_hook("key", %{"key" => message})

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Try to execute without binary file", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Binary.remove_bin_files(1)
    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Bin: Binary not found"
  end

  test "Terminal timed out", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    Binary.create_bin_files(1)
    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"

    assert [pid] = FixtureTerminal.list_children()

    send(pid, :session_timeout)

    assert_receive {:handle_ref_event, ^ref}, 1_000

    # Check it has changed back to /applications
    refute render(index_live) =~ "Bin: "
  end

  test "Coverage only - Ignore keys until it is connected" do
    socket = %{assigns: %{terminal_process: nil}}

    assert {:noreply, ^socket} = Terminal.handle_event("key", :any, socket)
  end
end
