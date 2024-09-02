defmodule DeployexWeb.Applications.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /applications", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> "test-topic" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, _lv, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "1.2.3"
    assert html =~ "4.5.6"
    assert html =~ "CONNECTED"
    assert html =~ "SUPPORTED"
    assert html =~ "FULL"
    assert html =~ "short time"
    assert html =~ "long time"
    assert html =~ "1.2.3 [running]"
  end

  test "GET /applications deployment: hot-upgrade", %{conn: conn} do
    topic = "topic-index-001"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "FULL"

    new_state = [
      Monitoring.deployex(),
      Monitoring.application(%{last_deployment: "hot_upgrade"})
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    assert render(view) =~ "HOT UPGRADE"
  end

  test "GET /applications restarts (crash and force)", %{conn: conn} do
    topic = "topic-index-002"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"

    assert html =~
             "Crash Restart</span><span class=\"bg-gray-100 text-white-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-white border border-gray-500\">\n      0"

    assert html =~
             "Force Restart</span><span class=\"bg-gray-100 text-white-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-white border border-gray-500\">\n      0"

    new_state = [
      Monitoring.deployex(),
      Monitoring.application(%{crash_restart_count: 1, force_restart_count: 1})
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    assert render(view) =~
             "Crash Restart</span><span class=\"bg-red-100 text-red-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-red-400 border border-red-500 animate-pulse\">\n      1"

    assert render(view) =~
             "Force Restart</span><span class=\"bg-red-100 text-red-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-red-400 border border-red-500 animate-pulse\">\n      1"
  end

  test "GET /applications OTP not connected", %{conn: conn} do
    topic = "topic-index-003"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "CONNECTED"
    refute html =~ "NOT CONNECTED"

    new_state = [
      Monitoring.deployex(),
      Monitoring.application(%{otp: :not_connected})
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    assert render(view) =~ "NOT CONNECTED"
  end

  test "GET /applications TLS not supported", %{conn: conn} do
    topic = "topic-index-004"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "SUPPORTED"
    refute html =~ "NOT SUPPORTED"

    new_state = [
      Monitoring.deployex(%{tls: :not_supported}),
      Monitoring.application()
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    assert render(view) =~ "NOT SUPPORTED"
  end

  test "GET /applications application states", %{conn: conn} do
    topic = "topic-index-005"

    Deployex.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         Monitoring.deployex(),
         Monitoring.application(%{status: :idle, version: nil})
       ]}
    end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "version not set"
    assert html =~ "bg-gray-400"

    new_state = [
      Monitoring.deployex(),
      Monitoring.application(%{status: :starting, version: "1.0.0"})
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    html = render(view)
    assert html =~ "1.0.0 [starting]"
    assert html =~ "bg-gray-400"

    new_state = [
      Monitoring.deployex(),
      Monitoring.application(%{status: :pre_commands, version: "1.0.0"})
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    html = render(view)
    assert html =~ "1.0.0 [pre-commands]"
    assert html =~ "bg-gray-400"

    new_state = [
      Monitoring.deployex(),
      Monitoring.application(%{status: :running, version: "1.0.0"})
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    html = render(view)
    assert html =~ "1.0.0 [running]"
    refute html =~ "bg-gray-400"
    assert html =~ "bg-gradient-to-r from-cyan-200 to-yellow-100"
  end
end
