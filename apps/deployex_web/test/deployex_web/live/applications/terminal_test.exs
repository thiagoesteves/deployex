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

  alias Deployer.Fixture.Files, as: FixtureFiles
  alias DeployexWeb.ApplicationsLive.Terminal
  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias DeployexWeb.Helper
  alias Foundation.Catalog
  alias Host.Fixture.Terminal, as: FixtureTerminal

  test "Access to terminal for Deployex", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    name = "deployex"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, [FixtureStatus.deployex()]} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> [] end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, test_pid_process, os_pid} end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    FixtureFiles.create_deployex_bin_files()

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-#{name}") |> render_click() =~
             "Bin: /tmp/deployex/test/opt/#{name}"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Access to terminal for Elixir apps", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    name = "myelixir"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.node_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> [] end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    FixtureFiles.create_bin_files(sname)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-#{name_id}-#{suffix}") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/bin/#{name}"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Access to terminal for Gleam apps", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    name = "mygleam"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.node_info()
    app_lang = "gleam"

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{name: name, sname: sname, language: app_lang})
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    FixtureFiles.create_bin_files(app_lang, sname)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-#{name_id}-#{suffix}") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/erlang-shipment"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Access to terminal for Erlang apps", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    name = "myerlang"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.node_info()
    app_lang = "erlang"

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{name: name, sname: sname, language: app_lang})
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    FixtureFiles.create_bin_files(app_lang, sname)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-#{name_id}-#{suffix}") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/bin/#{name}"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Invalid cookie", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    name = "myelixir"
    name_id = Helper.normalize_id(name)

    %{sname: sname, suffix: suffix, node: node} =
      name |> Catalog.create_sname() |> Catalog.node_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> [] end)

    Host.CommanderMock
    |> expect(:run, 1, fn _command, _options ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      {:error, :invalid_cookie}
    end)

    assert capture_log(fn ->
             {:ok, index_live, _html} = live(conn, ~p"/applications")

             FixtureFiles.create_bin_files(sname)

             assert index_live |> element("#app-terminal-#{name_id}-#{suffix}") |> render_click() =~
                      "Terminal for #{sname}"

             assert_receive {:handle_ref_event, ^ref}, 1_000
           end) =~
             "Error while trying to run the commands for node: #{node} - :iex_terminal, reason: {:error, :invalid_cookie}"
  end

  test "Send Character to iex terminal", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    message = "Opening Terminal"
    name = "myelixir"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.node_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> [] end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options -> {:ok, test_pid_process, os_pid} end)
    |> expect(:send, fn ^os_pid, ^message ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)
    |> expect(:stop, fn ^os_pid -> :ok end)

    FixtureFiles.create_bin_files(sname)
    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-#{name_id}-#{suffix}") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/bin/#{name}"

    # NOTE: Force handle_event in the live component
    index_live
    |> element("#iex-#{sname}")
    |> render_hook("key", %{"key" => message})

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Try to execute without binary file", %{conn: conn} do
    name = "myelixir"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.node_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{name: name, sname: sname})
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> [] end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-#{name_id}-#{suffix}") |> render_click() =~
             "Bin: Binary not found"
  end

  test "Terminal timed out", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    name = "myelixir"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.node_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> [] end)

    Host.CommanderMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    FixtureFiles.create_bin_files(sname)
    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-#{name_id}-#{suffix}") |> render_click() =~
             "Bin: /tmp/deployex/test/varlib/service/#{name}/#{sname}/current/bin/#{name}"

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
    name = "myelixir"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.node_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    FixtureFiles.create_bin_files(sname)

    with_mock Foundation.Common, [:passthrough], cookie: fn -> :nocookie end do
      {:ok, index_live, _html} = live(conn, ~p"/applications")

      assert index_live |> element("#app-terminal-#{name_id}-#{suffix}") |> render_click() =~
               "Bin: Cookie not set"
    end
  end
end
