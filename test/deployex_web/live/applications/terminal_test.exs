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
  alias Deployex.Terminal.Server
  alias DeployexWeb.ApplicationsLive.Terminal

  test "Access to terminal by instance", %{conn: conn} do
    topic = "topic-terminal-000"

    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Erlang cookie"

    Binary.create_bin_files(1)

    assert index_live
           |> form("#terminal-form-1", %{"cookie" => "Some cookie"})
           |> render_submit() =~
             "Bin: /tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"

    assert :ok =
             Server.async_terminate(%Deployex.Terminal.Server{instance: "1", type: :iex_terminal})

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Maximum number of terminals reached", %{conn: conn} do
    topic = "topic-terminal-001"

    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    assert capture_log(fn ->
             assert {:ok, _pid} =
                      Deployex.Terminal.Supervisor.new(%Deployex.Terminal.Server{
                        instance: "1",
                        commands: "",
                        options: [],
                        target: self(),
                        type: :iex_terminal
                      })

             {:ok, index_live, _html} = live(conn, ~p"/applications")

             assert index_live |> element("#app-terminal-1") |> render_click() =~
                      "Erlang cookie"

             Binary.create_bin_files(1)

             index_live
             |> form("#terminal-form-1", %{"cookie" => "Some cookie"})
             |> render_submit()

             assert :ok =
                      Server.async_terminate(%Deployex.Terminal.Server{
                        instance: "1",
                        type: :iex_terminal
                      })

             assert_receive {:handle_ref_event, ^ref}, 1_000
           end) =~ "Maximum number of terminals achieved for instance: 1 type: :iex_terminal"
  end

  test "Empty cookie", %{conn: conn} do
    topic = "topic-terminal-002"

    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, 0, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, 0, fn ^os_pid ->
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Erlang cookie"

    Binary.create_bin_files(1)

    refute index_live
           |> form("#terminal-form-1", %{"cookie" => ""})
           |> render_submit() =~
             "Bin: /tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"
  end

  test "Invalid cookie", %{conn: conn} do
    topic = "topic-terminal-003"

    ref = make_ref()
    test_pid_process = self()

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, 1, fn _command, _options ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      {:error, :invalid_cookie}
    end)

    assert capture_log(fn ->
             {:ok, index_live, _html} = live(conn, ~p"/applications")

             assert index_live |> element("#app-terminal-1") |> render_click() =~
                      "Erlang cookie"

             Binary.create_bin_files(1)

             index_live
             |> form("#terminal-form-1", %{"cookie" => "invalid-cookie"})
             |> render_submit()

             assert_receive {:handle_ref_event, ^ref}, 1_000

             assert :undefined == :global.whereis_name(%{type: :iex_terminal, instance: "1"})
           end) =~
             "Error while trying to run the commands for instance: 1, reason: {:error, :invalid_cookie}"
  end

  test "Send Character to iex terminal", %{conn: conn} do
    topic = "topic-terminal-004"

    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456
    message = "Opening Terminal"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options -> {:ok, test_pid_process, os_pid} end)
    |> expect(:send, fn ^os_pid, ^message ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)
    |> expect(:stop, fn ^os_pid -> :ok end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Erlang cookie"

    Binary.create_bin_files(1)

    assert index_live
           |> form("#terminal-form-1", %{"cookie" => "Some cookie"})
           |> render_submit() =~
             "Bin: /tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"

    # NOTE: Force handle_event in the live component
    index_live
    |> element("#iex-1")
    |> render_hook("key", %{"key" => message})

    assert :ok =
             Server.async_terminate(%Deployex.Terminal.Server{instance: "1", type: :iex_terminal})

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Try to execute without binary file", %{conn: conn} do
    topic = "topic-terminal-005"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Erlang cookie"

    Binary.remove_bin_files(1)

    assert index_live
           |> form("#terminal-form-1", %{"cookie" => "Some cookie"})
           |> render_submit() =~
             "Bin: Binary not found"
  end

  test "Terminal timed out", %{conn: conn} do
    topic = "topic-terminal-006"

    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    Deployex.OpSysMock
    |> expect(:run, fn _command, _options ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-terminal-1") |> render_click() =~
             "Erlang cookie"

    Binary.create_bin_files(1)

    assert index_live
           |> form("#terminal-form-1", %{"cookie" => "Some cookie"})
           |> render_submit() =~
             "Bin: /tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"

    pid = :global.whereis_name(%{type: :iex_terminal, instance: "1"})
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
