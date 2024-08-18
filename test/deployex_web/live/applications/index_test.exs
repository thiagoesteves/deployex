defmodule DeployexWeb.Applications.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  @deployex_status %Deployex.Status{
    name: "deployex",
    version: "1.2.3",
    otp: :connected,
    tls: :supported,
    supervisor: true,
    status: :running,
    uptime: "short time",
    last_ghosted_version: "-/-"
  }

  @application_status %Deployex.Status{
    name: "my-test-app",
    instance: 1,
    version: "4.5.6",
    otp: :connected,
    tls: :supported,
    last_deployment: "full_deployment",
    supervisor: false,
    status: :running,
    restarts: 0,
    uptime: "long time"
  }

  test "GET /applications", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{monitoring: [@deployex_status, @application_status]}} end)
    |> expect(:listener_topic, fn -> "test-topic" end)

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
    topic = "topic-test-001"

    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{monitoring: [@deployex_status, @application_status]}} end)
    |> expect(:listener_topic, fn -> topic end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "FULL"

    new_state = [
      @deployex_status,
      @application_status |> Map.put(:last_deployment, "hot_upgrade")
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    assert render(view) =~ "HOT UPGRADE"
  end

  test "GET /applications restarts", %{conn: conn} do
    topic = "topic-test-002"

    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{monitoring: [@deployex_status, @application_status]}} end)
    |> expect(:listener_topic, fn -> topic end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"

    assert html =~
             "Restarts</span><span class=\"bg-gray-100 text-white-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-white border border-gray-500\">\n      0"

    new_state = [
      @deployex_status,
      @application_status |> Map.put(:restarts, 1)
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    assert render(view) =~
             "Restarts</span><span class=\"bg-red-100 text-red-800 text-xs font-medium me-2 px-2.5 py-0.5 rounded dark:bg-gray-700 dark:text-red-400 border border-red-500 animate-pulse\">\n      1"
  end

  test "GET /applications OTP not connected", %{conn: conn} do
    topic = "topic-test-003"

    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{monitoring: [@deployex_status, @application_status]}} end)
    |> expect(:listener_topic, fn -> topic end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "CONNECTED"
    refute html =~ "NOT CONNECTED"

    new_state = [
      @deployex_status,
      @application_status |> Map.put(:otp, :not_connected)
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    assert render(view) =~ "NOT CONNECTED"
  end

  test "GET /applications TLS not supported", %{conn: conn} do
    topic = "topic-test-004"

    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{monitoring: [@deployex_status, @application_status]}} end)
    |> expect(:listener_topic, fn -> topic end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "SUPPORTED"
    refute html =~ "NOT SUPPORTED"

    new_state = [
      @deployex_status |> Map.put(:tls, :not_supported),
      @application_status
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    assert render(view) =~ "NOT SUPPORTED"
  end

  test "GET /applications application states", %{conn: conn} do
    topic = "topic-test-005"

    Deployex.StatusMock
    |> expect(:state, fn ->
      {:ok,
       %{
         monitoring: [
           @deployex_status,
           @application_status
           |> Map.put(:status, :idle)
           |> Map.put(:version, nil)
         ]
       }}
    end)
    |> expect(:listener_topic, fn -> topic end)

    {:ok, view, html} = live(conn, ~p"/applications")

    assert html =~ "Listing Applications"
    assert html =~ "version not set"
    assert html =~ "bg-gray-400"

    new_state = [
      @deployex_status,
      @application_status
      |> Map.put(:status, :starting)
      |> Map.put(:version, "1.0.0")
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    html = render(view)
    assert html =~ "1.0.0 [starting]"
    assert html =~ "bg-gray-400"

    new_state = [
      @deployex_status,
      @application_status
      |> Map.put(:status, :pre_commands)
      |> Map.put(:version, "1.0.0")
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    html = render(view)
    assert html =~ "1.0.0 [pre-commands]"
    assert html =~ "bg-gray-400"

    new_state = [
      @deployex_status,
      @application_status
      |> Map.put(:status, :running)
      |> Map.put(:version, "1.0.0")
    ]

    Phoenix.PubSub.broadcast(Deployex.PubSub, topic, {:monitoring_app_updated, new_state})

    html = render(view)
    assert html =~ "1.0.0 [running]"
    refute html =~ "bg-gray-400"
    assert html =~ "bg-gradient-to-r from-cyan-200 to-yellow-100"
  end
end
