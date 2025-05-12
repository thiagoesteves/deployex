defmodule DeployexWeb.Applications.TerminalTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import Mox
  import Mock

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  alias DeployexWeb.ApplicationsLive.Terminal
  alias DeployexWeb.Fixture.Binary
  alias DeployexWeb.Fixture.Nodes, as: FixtureNodes
  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias DeployexWeb.Fixture.Terminal, as: FixtureTerminal

  test "Access to terminal by instance", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    node = FixtureNodes.test_node("test_app", "abc123")

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    Binary.create_bin_files(node)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-test-app-abc123") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/test_app/test_app-abc123/current/bin/test_app"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Access to terminal by instance - Gleam", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    name = "test_app"
    suffix = "abc123"
    sname = "#{name}-#{suffix}"
    node = FixtureNodes.test_node(name, suffix)
    app_lang = "gleam"

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{name: name, sname: sname, node: node, language: app_lang})
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    with_mock Foundation.Catalog.Local, [:passthrough], monitored_app_lang: fn -> app_lang end do
      Binary.create_bin_files(app_lang, node)

      {:ok, index_live, _html} = live(conn, ~p"/applications")

      assert index_live |> element("#app-terminal-test-app-abc123") |> render_click() =~
               "Bin: /tmp/deployex/test/varlib/service/test_app/test_app-abc123/current/erlang-shipment"

      FixtureTerminal.terminate_all()

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end
  end

  test "Access to terminal by instance - Erlang", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    name = "test_app"
    suffix = "abc123"
    sname = "#{name}-#{suffix}"
    node = FixtureNodes.test_node(name, suffix)
    app_lang = "erlang"

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{name: name, sname: sname, node: node, language: app_lang})
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    with_mock Foundation.Catalog.Local, [:passthrough], monitored_app_lang: fn -> app_lang end do
      Binary.create_bin_files(app_lang, node)

      {:ok, index_live, _html} = live(conn, ~p"/applications")

      assert index_live |> element("#app-terminal-test-app-abc123") |> render_click() =~
               "Bin: /tmp/deployex/test/varlib/service/test_app/test_app-abc123/current/bin/test_app"

      FixtureTerminal.terminate_all()

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end
  end

  test "Invalid cookie", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    node = FixtureNodes.test_node("test_app", "abc123")

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Host.CommanderMock
    |> expect(:run, 1, fn _command, _options ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      {:error, :invalid_cookie}
    end)

    assert capture_log(fn ->
             {:ok, index_live, _html} = live(conn, ~p"/applications")

             Binary.create_bin_files(node)

             assert index_live |> element("#app-terminal-test-app-abc123") |> render_click() =~
                      "Terminal for test_app-abc123"

             assert_receive {:handle_ref_event, ^ref}, 1_000
           end) =~
             "Error while trying to run the commands for node: #{node} - :iex_terminal, reason: {:error, :invalid_cookie}"
  end

  test "Send Character to iex terminal", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    message = "Opening Terminal"
    node = FixtureNodes.test_node("test_app", "abc123")

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, test_pid_process, os_pid} end)
    |> expect(:send, fn ^os_pid, ^message ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)
    |> expect(:stop, fn ^os_pid -> :ok end)

    Binary.create_bin_files(node)
    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-test-app-abc123") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/test_app/test_app-abc123/current/bin/test_app"

    # NOTE: Force handle_event in the live component
    index_live
    |> element("#iex-test_app-abc123")
    |> render_hook("key", %{"key" => message})

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Try to execute without binary file", %{conn: conn} do
    name = "app"
    suffix = "123abc"
    sname = "#{name}-#{suffix}"
    node = FixtureNodes.test_node(name, suffix)

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{name: name, sname: sname, node: node})
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    # Binary.create_bin_files(node)
    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-app-123abc") |> render_click() =~
             "Bin: Binary not found"
  end

  test "Terminal timed out", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    node = FixtureNodes.test_node("test_app", "abc123")

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    Binary.create_bin_files(node)
    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-test-app-abc123") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/test_app/test_app-abc123/current/bin/test_app"

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

  test "Error when :nocookie is set", %{conn: conn} do
    node = FixtureNodes.test_node("test_app", "abc123")

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Binary.create_bin_files(node)

    with_mock Foundation.Common, cookie: fn -> :nocookie end do
      {:ok, index_live, _html} = live(conn, ~p"/applications")

      assert index_live |> element("#app-terminal-test-app-abc123") |> render_click() =~
               "Bin: Cookie not set"
    end
  end
end
