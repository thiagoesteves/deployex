defmodule DeployexWeb.Applications.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Deployer.Resources
  alias Deployer.Resources.Limit
  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  @ghosted_config %{
    last_ghosted_version: "4.6.0",
    last_ghosted_at: ~U[2026-10-28 14:20:00Z],
    mode: :automatic,
    manual_version: nil,
    versions: []
  }

  defp resources(attrs \\ %{}) do
    Map.merge(
      %Resources{
        sname: "myphoenixapp-abc123",
        cpu: 12,
        memory: 849_346_560,
        process: %Limit{count: 212_377, limit: 262_144, percent: 81},
        port: %Limit{count: 40, limit: 65_536, percent: 0},
        atom: %Limit{
          count: 61_204,
          limit: 1_048_576,
          percent: 5,
          change_percent: 15,
          change_minutes: 60
        }
      },
      attrs
    )
  end

  defp stub_monitoring(apps) do
    test_pid = self()

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, [FixtureStatus.deployex() | apps]} end)
    |> expect(:subscribe, fn ->
      send(test_pid, {:liveview_pid, self()})
      :ok
    end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)
  end

  @tag :capture_log
  test "GET /applications shows the host card and one row per app", %{conn: conn} do
    stub_monitoring([
      FixtureStatus.application(%{
        name: "myphoenixapp",
        deployed_at: DateTime.add(DateTime.utc_now(), -2, :hour),
        resources: resources()
      })
    ])

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "<h1"
    assert html =~ "Applications"
    assert html =~ "DeployEx"
    assert html =~ "1.2.3"
    assert html =~ "on OTP #{System.otp_release()}"
    assert html =~ "myphoenixapp"
    assert html =~ "4.5.6 · OTP 27 · Elixir 1.20"
    assert html =~ "1/1 running"
    assert html =~ "12%"
    assert html =~ "810 MB"
    assert html =~ "2h ago"
    assert html =~ "dx-dtag-full"
    refute html =~ "needs attention"

    # The problems of the instances show as a count on the row, which opens the instances
    assert html =~ "myphoenixapp-abc123 processes at 81% of the limit"
    assert html =~ "myphoenixapp-abc123 atoms grew 15% in 1 hour"
    assert html =~ ~s(aria-label="2 problems: myphoenixapp-abc123 processes)

    view |> element("#app-myphoenixapp-problems") |> render_click()
    assert has_element?(view, "#instance-myphoenixapp-abc123")
    view |> element("#app-myphoenixapp-problems") |> render_click()
    assert has_element?(view, "#instance-myphoenixapp-abc123")
    view |> element("#app-myphoenixapp-toggle") |> render_click()

    # The instances open with the chevron, each with its limits closed, also near a limit
    html = view |> element("#app-myphoenixapp-toggle") |> render_click()
    assert html =~ "myphoenixapp-abc123"
    assert html =~ "IEx shell"
    assert html =~ "myphoenixapp-abc123 processes at 81% of the limit"
    refute html =~ "212,377 of 262,144"

    html = view |> element("#instance-myphoenixapp-abc123-limits") |> render_click()
    assert html =~ "212,377 of 262,144"
    assert html =~ "+15% in 1 hour"

    html = view |> element("#instance-myphoenixapp-abc123-limits") |> render_click()
    refute html =~ "212,377 of 262,144"

    view |> element("#app-myphoenixapp-toggle") |> render_click()
    refute has_element?(view, "#instance-myphoenixapp-abc123-limits")
  end

  @tag :capture_log
  test "GET /applications shows a ghosted version under its app, and clears it after the Undo window",
       %{conn: conn} do
    test_pid = self()

    stub_monitoring([
      FixtureStatus.application(
        %{name: "myerlangapp", language: "erlang", status: :idle},
        @ghosted_config
      )
    ])

    Deployer.StatusMock
    |> stub(:remove_ghosted_version, fn "myerlangapp", "4.6.0" ->
      send(test_pid, :removed)
      {:ok, []}
    end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "1 app needs attention"
    assert html =~ "4.6.0 failed and is ghosted. No earlier version runs on this host."
    assert html =~ "0/1 running"
    assert html =~ "dx-dtag-fail"
    assert html =~ "14:20"

    # Undo puts it back before anything is cleared
    html = view |> element("#app-myerlangapp-clear-ghosted") |> render_click()
    assert html =~ "Cleared ghosted 4.6.0"
    html = view |> element("#app-myerlangapp-undo-clear") |> render_click()
    assert html =~ "4.6.0 failed and is ghosted"
    refute_received :removed

    # Without Undo, the clear happens when the window ends
    view |> element("#app-myerlangapp-clear-ghosted") |> render_click()
    send(view.pid, {:commit_clear, "myerlangapp"})
    assert_receive :removed

    # A second commit for the same app does nothing
    send(view.pid, {:commit_clear, "myerlangapp"})
    assert render(view) =~ "myerlangapp"
  end

  @tag :capture_log
  test "GET /applications restarts an instance after an inline confirmation", %{conn: conn} do
    test_pid = self()
    stub_monitoring([FixtureStatus.application(%{name: "myphoenixapp"})])

    Deployer.MonitorMock
    |> expect(:restart, fn "myphoenixapp-abc123" ->
      send(test_pid, :restarted)
      :ok
    end)

    {:ok, view, _html} = live(conn, ~p"/applications")
    view |> element("#app-myphoenixapp-toggle") |> render_click()

    html = view |> element("#instance-myphoenixapp-abc123-restart") |> render_click()
    assert html =~ "Restart myphoenixapp-abc123?"

    html = view |> element("button", "Cancel") |> render_click()
    refute html =~ "Restart myphoenixapp-abc123?"

    view |> element("#instance-myphoenixapp-abc123-restart") |> render_click()
    html = view |> element("#instance-myphoenixapp-abc123-restart-confirm") |> render_click()

    assert_receive :restarted
    assert html =~ "Restart sent"
  end

  @tag :capture_log
  test "GET /applications restarts every instance of an app after an inline confirmation", %{
    conn: conn
  } do
    stub_monitoring([FixtureStatus.application(%{name: "myphoenixapp"})])

    {:ok, view, _html} = live(conn, ~p"/applications")
    view |> element("#app-myphoenixapp-toggle") |> render_click()

    html = view |> element("#app-myphoenixapp-restart-all") |> render_click()
    assert html =~ "Restart every instance of myphoenixapp?"

    html = view |> element("#app-myphoenixapp-restart-all-confirm") |> render_click()
    assert html =~ "Restarting every instance of myphoenixapp"
  end

  @tag :capture_log
  test "GET /applications restarts DeployEx after an inline confirmation", %{conn: conn} do
    stub_monitoring([])

    {:ok, view, html} = live(conn, ~p"/applications")
    assert html =~ "No applications on this host"
    assert html =~ ~s(href="/documentation?page=guide-local-elixir.html")
    assert html =~ ~s(href="/documentation?page=guide-yaml.html")

    html = view |> element("#host-restart") |> render_click()
    assert html =~ "Restart DeployEx?"

    # The DeployEx process this test runs in is not the one the kill looks for
    stub(Host.CommanderMock, :run, fn _command, _options -> {:ok, []} end)

    assert ExUnit.CaptureLog.capture_log(fn ->
             view |> element("#host-restart-confirm") |> render_click()
           end) =~ "Deployex was requested to terminate"

    refute render(view) =~ "Restart DeployEx?"
  end

  @tag :capture_log
  test "GET /applications follows this host's status updates only", %{conn: conn} do
    stub_monitoring([FixtureStatus.application(%{name: "myphoenixapp"})])

    {:ok, view, _html} = live(conn, ~p"/applications")
    assert_receive {:liveview_pid, pid}

    send(pid, {:monitoring_app_updated, :other@host, []})
    assert render(view) =~ "myphoenixapp"

    send(pid, {:monitoring_app_updated, Node.self(), [FixtureStatus.deployex()]})
    refute render(view) =~ "myphoenixapp"
  end

  @tag :capture_log
  test "GET /applications?app opens the app, and the instance's limits", %{conn: conn} do
    stub_monitoring([
      FixtureStatus.application(%{
        name: "myphoenixapp",
        resources: resources(%{process: nil, atom: nil})
      })
    ])

    {:ok, _view, html} =
      live(conn, ~p"/applications?app=myphoenixapp&instance=myphoenixapp-abc123")

    assert html =~ "myphoenixapp-abc123"
    assert html =~ "40 of 65,536"
  end

  @tag :capture_log
  test "GET /applications shows the starting and pre_commands states", %{conn: conn} do
    stub_monitoring([
      FixtureStatus.application(%{name: "myphoenixapp", status: :pre_commands, version: "4.7.0"})
    ])

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "myphoenixapp-abc123 runs its pre_commands for 4.7.0."
    html = view |> element("#app-myphoenixapp-toggle") |> render_click()
    assert html =~ "pre_commands 4.7.0"

    html = view |> element("#instance-myphoenixapp-abc123-limits") |> render_click()
    assert html =~ "No reading yet."
  end
end
