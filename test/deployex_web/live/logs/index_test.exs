defmodule DeployexWeb.Logs.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import Mock

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus
  alias Deployex.Fixture.Terminal, as: FixtureTerminal

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /applications check buttom", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live
           |> element("a", "Live Logs")
           |> render_click()
  end

  test "GET /logs", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/logs")

    assert html =~ "Live Logs"
  end

  test "Add Service + Stdout", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    expected_path = "/var/log/deployex/deployex-stdout.log"
    expected_cmd = "tail -f -n 0 /var/log/deployex/deployex-stdout.log"

    Deployex.OpSysMock
    |> expect(:run, fn ^expected_cmd, [:monitor, :stdout] ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs")

    with_mock File, exists?: fn ^expected_path -> true end do
      index_live
      |> element("#log-multi-select-toggle-options")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stdout-add-item")
      |> render_click()
    end

    FixtureTerminal.terminate_all()
    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Add Stdout + Service", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    expected_path = "/var/log/deployex/deployex-stdout.log"
    expected_cmd = "tail -f -n 0 /var/log/deployex/deployex-stdout.log"

    Deployex.OpSysMock
    |> expect(:run, fn ^expected_cmd, [:monitor, :stdout] ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs")

    with_mock File, exists?: fn ^expected_path -> true end do
      index_live
      |> element("#log-multi-select-toggle-options")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stdout-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-add-item")
      |> render_click()
    end

    FixtureTerminal.terminate_all()
    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Add/Remove Service + Stdout", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    expected_path = "/var/log/deployex/deployex-stdout.log"
    expected_cmd = "tail -f -n 0 /var/log/deployex/deployex-stdout.log"

    Deployex.OpSysMock
    |> expect(:run, fn ^expected_cmd, [:monitor, :stdout] ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs")

    with_mock File, exists?: fn ^expected_path -> true end do
      index_live
      |> element("#log-multi-select-toggle-options")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stdout-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-remove-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stdout-remove-item")
      |> render_click()
    end

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Add/Remove Stdout + Service", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    expected_path = "/var/log/deployex/deployex-stdout.log"
    expected_cmd = "tail -f -n 0 /var/log/deployex/deployex-stdout.log"

    Deployex.OpSysMock
    |> expect(:run, fn ^expected_cmd, [:monitor, :stdout] ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs")

    with_mock File, exists?: fn ^expected_path -> true end do
      index_live
      |> element("#log-multi-select-toggle-options")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stdout-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stdout-remove-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-remove-item")
      |> render_click()
    end

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  test "Add/Remove Stderr + Service", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    expected_path = "/var/log/deployex/deployex-stderr.log"
    expected_cmd = "tail -f -n 0 /var/log/deployex/deployex-stderr.log"

    Deployex.OpSysMock
    |> expect(:run, fn ^expected_cmd, [:monitor, :stdout] ->
      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs")

    with_mock File, exists?: fn ^expected_path -> true end do
      index_live
      |> element("#log-multi-select-toggle-options")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stderr-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-remove-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stderr-remove-item")
      |> render_click()
    end

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end

  %{
    1 => %{type: "debug", color: "#E5E5E5"},
    2 => %{type: "DEBUG", color: "#E5E5E5"},
    3 => %{type: "info", color: "#93C5FD"},
    4 => %{type: "INFO", color: "#93C5FD"},
    5 => %{type: "warning", color: "#FBBF24"},
    6 => %{type: "WARNING", color: "#FBBF24"},
    7 => %{type: "error", color: "#F87171"},
    8 => %{type: "ERROR", color: "#F87171"},
    9 => %{type: "SIGTERM", color: "#F87171"},
    10 => %{type: "notice", color: "#FDBA74"},
    11 => %{type: "NOTICE", color: "#FDBA74"},
    12 => %{type: "none", color: "#E5E5E5"}
  }
  |> Enum.each(fn {element, %{type: type, color: color}} ->
    test "#{element} - Send Stdout #{type} message from erlexec server", %{conn: conn} do
      ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456

      expected_path = "/var/log/deployex/deployex-stdout.log"
      expected_cmd = "tail -f -n 0 /var/log/deployex/deployex-stdout.log"
      message = unquote(type)
      expected_color = unquote(color)

      Deployex.OpSysMock
      |> expect(:run, fn ^expected_cmd, [:monitor, :stdout] ->
        Process.send_after(test_pid_process, {:handle_sending_message, ref}, 100)
        send(self(), {:stdout, os_pid, message})

        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:stop, fn ^os_pid ->
        Process.send_after(test_pid_process, {:handle_terminate_event, ref}, 100)
        :ok
      end)

      {:ok, index_live, _html} = live(conn, ~p"/logs")

      with_mock File, exists?: fn ^expected_path -> true end do
        index_live
        |> element("#log-multi-select-toggle-options")
        |> render_click()

        index_live
        |> element("#log-multi-select-logs-stdout-add-item")
        |> render_click()

        index_live
        |> element("#log-multi-select-services-deployex-add-item")
        |> render_click()
      end

      assert_receive {:handle_sending_message, ^ref}, 1_000

      assert render(index_live) =~ expected_color

      FixtureTerminal.terminate_all()
      assert_receive {:handle_terminate_event, ^ref}, 1_000
    end
  end)

  %{
    1 => %{type: "debug"},
    2 => %{type: "DEBUG"},
    3 => %{type: "info"},
    4 => %{type: "INFO"},
    5 => %{type: "warning"},
    6 => %{type: "WARNING"},
    7 => %{type: "error"},
    8 => %{type: "ERROR"},
    9 => %{type: "SIGTERM"},
    10 => %{type: "notice"},
    11 => %{type: "NOTICE"},
    12 => %{type: "none"}
  }
  |> Enum.each(fn {element, %{type: type}} ->
    test "#{element} - Send Stderr #{type} message from erlexec server", %{conn: conn} do
      ref = make_ref()
      test_pid_process = self()
      os_pid = 123_456

      expected_path = "/var/log/deployex/deployex-stderr.log"
      expected_cmd = "tail -f -n 0 /var/log/deployex/deployex-stderr.log"
      message = unquote(type)

      Deployex.OpSysMock
      |> expect(:run, fn ^expected_cmd, [:monitor, :stdout] ->
        Process.send_after(test_pid_process, {:handle_sending_message, ref}, 100)
        send(self(), {:stdout, os_pid, message})

        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:stop, fn ^os_pid ->
        Process.send_after(test_pid_process, {:handle_terminate_event, ref}, 100)
        :ok
      end)

      {:ok, index_live, _html} = live(conn, ~p"/logs")

      with_mock File, exists?: fn ^expected_path -> true end do
        index_live
        |> element("#log-multi-select-toggle-options")
        |> render_click()

        index_live
        |> element("#log-multi-select-logs-stderr-add-item")
        |> render_click()

        index_live
        |> element("#log-multi-select-services-deployex-add-item")
        |> render_click()
      end

      assert_receive {:handle_sending_message, ^ref}, 1_000

      assert render(index_live) =~ "#F87171"

      FixtureTerminal.terminate_all()
      assert_receive {:handle_terminate_event, ^ref}, 1_000
    end
  end)

  test "Reset Stream button", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    expected_path = "/var/log/deployex/deployex-stdout.log"
    expected_cmd = "tail -f -n 0 /var/log/deployex/deployex-stdout.log"
    message = "My beautiful message"

    Deployex.OpSysMock
    |> expect(:run, fn ^expected_cmd, [:monitor, :stdout] ->
      Process.send_after(test_pid_process, {:handle_sending_message, ref}, 100)
      send(self(), {:stdout, os_pid, message})

      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_terminate_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs")

    with_mock File, exists?: fn ^expected_path -> true end do
      index_live
      |> element("#log-multi-select-toggle-options")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stdout-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-add-item")
      |> render_click()
    end

    assert_receive {:handle_sending_message, ^ref}, 1_000

    assert render(index_live) =~ message

    index_live
    |> element("#log-multi-select-reset", "RESET")
    |> render_click()

    refute render(index_live) =~ message

    FixtureTerminal.terminate_all()
    assert_receive {:handle_terminate_event, ^ref}, 1_000
  end

  test "Receive :closed message from server", %{conn: conn} do
    ref = make_ref()
    test_pid_process = self()
    os_pid = 123_456

    expected_path = "/var/log/deployex/deployex-stdout.log"
    expected_cmd = "tail -f -n 0 /var/log/deployex/deployex-stdout.log"

    Deployex.OpSysMock
    |> expect(:run, fn ^expected_cmd, [:monitor, :stdout] ->
      send(self(), :session_timeout)

      {:ok, test_pid_process, os_pid}
    end)
    |> expect(:stop, fn ^os_pid ->
      Process.send_after(test_pid_process, {:handle_terminate_event, ref}, 100)
      :ok
    end)

    {:ok, index_live, _html} = live(conn, ~p"/logs")

    with_mock File, exists?: fn ^expected_path -> true end do
      index_live
      |> element("#log-multi-select-toggle-options")
      |> render_click()

      index_live
      |> element("#log-multi-select-logs-stdout-add-item")
      |> render_click()

      index_live
      |> element("#log-multi-select-services-deployex-add-item")
      |> render_click()
    end

    assert_receive {:handle_terminate_event, ^ref}, 1_000
  end
end
