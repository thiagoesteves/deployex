defmodule DeployexWeb.Applications.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /applications", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _lv, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "1.2.3"
    assert html =~ "4.5.6"
    assert html =~ "Connected"
    assert html =~ "Supported"
    assert html =~ "Full Deployment"
    assert html =~ "short time"
    assert html =~ "long time"
    assert html =~ "Running"
  end

  test "GET /applications deployment: hot-upgrade", %{conn: conn} do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "Full Deployment"

    new_state = [
      FixtureStatus.deployex(),
      FixtureStatus.application(%{last_deployment: "hot_upgrade"})
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    assert render(view) =~ "Hot Upgrade"
  end

  test "GET /applications restarts (crash and force)", %{conn: conn} do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"

    assert html =~
             "Crash Restarts</div></div><div class=\"flex items-center gap-1\"><div class=\"w-2 h-2 bg-neutral rounded-full\"></div><span class=\"text-sm font-medium text-neutral\">0"

    assert html =~
             "Force Restarts</div></div><div class=\"flex items-center gap-1\"><div class=\"w-2 h-2 bg-neutral rounded-full\"></div><span class=\"text-sm font-medium text-neutral\">0"

    new_state = [
      FixtureStatus.deployex(),
      FixtureStatus.application(%{crash_restart_count: 1, force_restart_count: 1})
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    assert render(view) =~
             "Crash Restarts</div></div><div class=\"flex items-center gap-1\"><div class=\"w-2 h-2 bg-error rounded-full animate-pulse\"></div><span class=\"text-sm font-semibold text-error\">1"

    assert render(view) =~
             "Force Restarts</div></div><div class=\"flex items-center gap-1\"><div class=\"w-2 h-2 bg-error rounded-full animate-pulse\"></div><span class=\"text-sm font-semibold text-error\">1"
  end

  test "GET /applications OTP not connected", %{conn: conn} do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "Connected"
    refute html =~ "Disconnected"

    new_state = [
      FixtureStatus.deployex(),
      FixtureStatus.application(%{otp: :not_connected})
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    assert render(view) =~ "Disconnected"
  end

  test "GET /applications TLS not supported", %{conn: conn} do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "Supported"
    refute html =~ "Not Supported"

    new_state = [
      %{tls: :not_supported} |> FixtureStatus.metadata_by_app() |> FixtureStatus.deployex(),
      FixtureStatus.application()
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    assert render(view) =~ "Not Supported"
  end

  test "GET /applications application states", %{conn: conn} do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{status: :idle, version: nil})
       ]}
    end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "Version not set"
    assert html =~ "bg-base-200/50 border-b border-base-200"

    new_state = [
      FixtureStatus.deployex(),
      FixtureStatus.application(%{status: :starting, version: "1.0.0"})
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    html = render(view)
    assert html =~ "Starting"
    assert html =~ "bg-warning/10 border-b border-warning/20"

    new_state = [
      FixtureStatus.deployex(),
      FixtureStatus.application(%{status: :pre_commands, version: "1.0.0"})
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    html = render(view)
    assert html =~ "Pre-commands"
    assert html =~ "bg-warning/10 border-b border-warning/20"

    new_state = [
      FixtureStatus.deployex(),
      FixtureStatus.application(%{status: :running, version: "1.0.0"})
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    html = render(view)
    assert html =~ "Running"
    assert html =~ "bg-success/10 border-b border-success/20"
  end

  test "GET /applications with no updates when receiving from other nodes", %{conn: conn} do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{status: :idle, version: nil})
       ]}
    end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "Version not set"
    assert html =~ "bg-base-200/50 border-b border-base-200"

    new_state = [
      FixtureStatus.deployex(),
      FixtureStatus.application(%{status: :starting, version: "1.0.0"})
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, :invalid@nohost, new_state}
    )

    html = render(view)
    refute html =~ "Starting"
  end
end
