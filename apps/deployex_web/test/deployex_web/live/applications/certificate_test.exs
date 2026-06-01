defmodule DeployexWeb.Applications.CertificateTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  # ---------------------------------------------------------------------------
  # mTLS supported indicator (deployex card only, driven by tls: field)
  # ---------------------------------------------------------------------------

  @tag :capture_log
  test "GET /applications deployex card shows mTLS as supported when tls is present", %{
    conn: conn
  } do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    assert html =~ "Supported"
    refute html =~ "Not Supported"
  end

  @tag :capture_log
  test "GET /applications deployex card shows mTLS as not supported when tls is nil", %{
    conn: conn
  } do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    new_state = [
      %{tls: nil, certificates: []}
      |> FixtureStatus.config_by_app()
      |> FixtureStatus.deployex(),
      FixtureStatus.application()
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    html = render(liveview)
    assert html =~ "Not Supported"
  end

  # ---------------------------------------------------------------------------
  # CertificatePanel (driven by certificates: field on both deployex and apps)
  # ---------------------------------------------------------------------------

  @tag :capture_log
  test "GET /applications certificate panel is not rendered when certificates list is empty", %{
    conn: conn
  } do
    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         %{tls: nil, certificates: []}
         |> FixtureStatus.config_by_app()
         |> FixtureStatus.deployex(),
         FixtureStatus.application()
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    refute html =~ "View details"
    refute html =~ "mTLS certificate"
  end

  @tag :capture_log
  test "GET /applications certificate panel is rendered when certificates list is present", %{
    conn: conn
  } do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    assert html =~ "mTLS certificate"
    assert html =~ "View details"
  end

  @tag :capture_log
  test "GET /applications certificate panel displays summary fields", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    assert html =~ "Issuer"
    assert html =~ "Expires in"
    assert html =~ "Domains"
    assert html =~ "Public key"
  end

  @tag :capture_log
  test "GET /applications certificate panel displays certificate values from fixture", %{
    conn: conn
  } do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    deployex = FixtureStatus.deployex()
    # certificates: list is what drives the panel, not tls:
    [cert | _] = deployex.certificates

    assert html =~ cert.issuer
    assert html =~ cert.public_key_type
  end

  @tag :capture_log
  test "GET /applications certificate panel displays covered domains count", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    deployex = FixtureStatus.deployex()
    [cert | _] = deployex.certificates
    domain_count = length(cert.domains)

    assert html =~ "#{domain_count} covered"
  end

  @tag :capture_log
  test "GET /applications certificate panel shows active badge when expiry is more than 30 days",
       %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    assert html =~ "active"
    assert html =~ "text-success"
    refute html =~ "expires soon"
  end

  @tag :capture_log
  test "GET /applications certificate panel shows expires soon badge when expiry is less than 30 days",
       %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         %{
           tls: FixtureStatus.certificate(%{expires_in_days: 10}),
           certificates: [FixtureStatus.certificate(%{expires_in_days: 10})]
         }
         |> FixtureStatus.config_by_app()
         |> FixtureStatus.deployex(),
         FixtureStatus.application()
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    assert html =~ "expires soon"
    assert html =~ "bg-error/5"
    assert html =~ "border-error/30"
    assert html =~ "text-error"
  end

  @tag :capture_log
  test "GET /applications certificate panel highlights expiry via pubsub when within 30 days", %{
    conn: conn
  } do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    expiring_cert = FixtureStatus.certificate(%{expires_in_days: 10})

    new_state = [
      FixtureStatus.deployex(%{tls: expiring_cert, certificates: [expiring_cert]}),
      FixtureStatus.application()
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    html = render(liveview)
    assert html =~ "10 days"
    assert html =~ "expires soon"
    assert html =~ "text-error"
    assert html =~ "bg-error/5"
    assert html =~ "border-error/30"
  end

  @tag :capture_log
  test "GET /applications certificate panel is removed via pubsub when certificates becomes empty",
       %{conn: conn} do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    new_state = [
      %{tls: nil, certificates: []}
      |> FixtureStatus.config_by_app()
      |> FixtureStatus.deployex(),
      FixtureStatus.application()
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    html = render(liveview)
    refute html =~ "View details"
    refute html =~ "mTLS certificate"
  end

  @tag :capture_log
  test "GET /applications certificate detail modal opens on view details click", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    assert liveview |> element("button[phx-click='show-app-certificate']") |> has_element?()

    liveview |> element("button[phx-click='show-app-certificate']") |> render_click()

    assert liveview |> element("#certificate-modal") |> has_element?()
    assert render(liveview) =~ "Certificate details"
  end

  @tag :capture_log
  test "GET /applications certificate modal closes on cancel button click", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    liveview |> element("button[phx-click='show-app-certificate']") |> render_click()
    assert liveview |> element("#certificate-modal") |> has_element?()

    liveview |> element(".modal-action .btn") |> render_click()

    refute liveview |> element("#certificate-modal") |> has_element?()
  end

  @tag :capture_log
  test "GET /applications certificate modal closes on backdrop click", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    liveview |> element("button[phx-click='show-app-certificate']") |> render_click()
    assert liveview |> element("#certificate-modal") |> has_element?()

    liveview |> element(".modal-backdrop") |> render_click()

    refute liveview |> element("#certificate-modal") |> has_element?()
  end
end
