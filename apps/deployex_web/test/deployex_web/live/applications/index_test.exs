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
      %{tls: :not_supported} |> FixtureStatus.config_by_app() |> FixtureStatus.deployex(),
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

  test "GET /applications with monitoring enabled", %{conn: conn} do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{
           monitoring: add_metrics([:port, :process, :atom, :memory, :new])
         })
       ]}
    end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "Auto-restart enabled"

    new_state = [
      FixtureStatus.deployex(),
      FixtureStatus.application(%{
        monitoring: add_metrics([:port, :process, :atom, :memory, :new], false)
      })
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    html = render(view)
    assert html =~ "Auto-restart disabled"
  end

  %{
    1 => %{metric: :port},
    2 => %{metric: :process},
    3 => %{metric: :atom},
    4 => %{metric: :memory}
  }
  |> Enum.each(fn {element, %{metric: metric}} ->
    test "#{element} - GET /applications with monitoring enabled and validating thresholds for metric: #{metric}",
         %{
           conn: conn
         } do
      topic = "test-topic"
      metric = unquote(metric)

      %{children: [application]} =
        status_app = FixtureStatus.application(%{monitoring: add_metrics([metric])})

      Deployer.StatusMock
      |> expect(:monitoring, fn -> {:ok, [FixtureStatus.deployex(), status_app]} end)
      |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
      |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

      {:ok, view, html} = live(conn, ~p"/applications")

      assert html =~ "Listing Applications"
      assert html =~ "Warning: 10%"
      assert html =~ "Restart: 20%"

      # Normal
      value = build_telemetry_data(8)

      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        topic,
        {:metrics_new_data, application.node, "vm.#{metric}.total", value}
      )

      html = render(view)
      assert html =~ "text-success\">\n          8%"

      # Warning
      value = build_telemetry_data(11)

      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        topic,
        {:metrics_new_data, application.node, "vm.#{metric}.total", value}
      )

      html = render(view)
      assert html =~ "text-warning\">\n          11%"

      # Restart
      value = build_telemetry_data(21)

      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        topic,
        {:metrics_new_data, application.node, "vm.#{metric}.total", value}
      )

      html = render(view)
      assert html =~ "text-error\">\n          21%"

      # Send invalid node, state doesn't change
      value = build_telemetry_data(8)

      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        topic,
        {:metrics_new_data, :invalid@host, "vm.#{metric}.total", value}
      )

      html = render(view)
      assert html =~ "text-error\">\n          21%"

      # Send invalid data, state doesn't change
      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        topic,
        {:metrics_new_data, :invalid@host, "vm.#{metric}.total", %{}}
      )

      html = render(view)
      assert html =~ "text-error\">\n          21%"

      # Normalize threshold
      value = build_telemetry_data(8)

      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        topic,
        {:metrics_new_data, application.node, "vm.#{metric}.total", value}
      )

      html = render(view)
      assert html =~ "text-success\">\n          8%"
    end
  end)

  defp add_metrics(metrics, enabled \\ true) do
    Enum.map(metrics, fn metric ->
      {metric,
       %{
         enable_restart: enabled,
         warning_threshold_percent: 10,
         restart_threshold_percent: 20
       }}
    end)
  end

  def build_telemetry_data(percentage, timestamp \\ :rand.uniform(2_000_000_000_000)) do
    limit = 80_000
    value = trunc(percentage / 100 * limit)

    %ObserverWeb.Telemetry.Data{
      timestamp: timestamp,
      value: value / 1000,
      unit: " kilobyte",
      tags: %{},
      measurements: %{
        limit: limit,
        total: value
      }
    }
  end
end
