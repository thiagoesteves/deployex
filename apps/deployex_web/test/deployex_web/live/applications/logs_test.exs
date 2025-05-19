defmodule DeployexWeb.Applications.LogsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  alias Deployer.Fixture.Files, as: FixtureFiles
  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias DeployexWeb.Fixture.Terminal, as: FixtureTerminal
  alias DeployexWeb.Helper
  alias Foundation.Catalog

  test "Access to stdout logs by instance", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    name = "test_app"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.sname_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
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

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    Catalog.setup(sname)

    assert index_live |> element("#app-log-stdout-#{name_id}-#{suffix}") |> render_click() =~
             "Application Logs [#{name}-#{suffix}]"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Access to stderr logs by instance", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    name = "test_app"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.sname_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
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

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    Catalog.setup(sname)

    assert index_live |> element("#app-log-stderr-#{name_id}-#{suffix}") |> render_click() =~
             "Application Logs [#{name}-#{suffix}]"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Redirect received string to JS [stdout]", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    name = "test_app"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.sname_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
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

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    Catalog.setup(sname)

    assert index_live |> element("#app-log-stdout-#{name_id}-#{suffix}") |> render_click() =~
             "Application Logs [#{name}-#{suffix}]"

    message = "[info] my-info-message"
    update_log_message(os_pid, message)

    assert render(index_live) =~ message
    assert render(index_live) =~ "#93C5FD"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Redirect received string to JS [stderr]", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    name = "test_app"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.sname_info()

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
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

    FixtureFiles.create_log_files(sname)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-log-stderr-#{name_id}-#{suffix}") |> render_click() =~
             "Application Logs [#{name}-#{suffix}]"

    message = "[info] my-info-message"
    update_log_message(os_pid, message)

    assert render(index_live) =~ message
    assert render(index_live) =~ "#F87171"

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Error accessing deployex logs [this logs are available ony in production]", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert html = index_live |> element("#app-log-stdout-deployex") |> render_click()
    assert html =~ "Application Logs [deployex]"
    assert html =~ "File not found"
  end

  defp update_log_message(os_pid, message) do
    [pid] = FixtureTerminal.list_children()
    send(pid, {:stdout, os_pid, "\rtime #{message}"})
    # Wait the page for the update
    :timer.sleep(10)
  end
end
