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

  test "GET /applications certificate modal is not visible on load", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    refute liveview |> element("#certificate-modal") |> has_element?()
  end

  test "GET /applications certificate modal opens on mTLS button click", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    assert liveview |> element("#show-tls-certificate-id") |> has_element?()

    liveview |> element("#show-tls-certificate-id") |> render_click()

    assert liveview |> element("#certificate-modal") |> has_element?()
    assert render(liveview) =~ "mTLS Certificate Details"
  end

  test "GET /applications certificate modal displays all certificate fields", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    liveview |> element("#show-tls-certificate-id") |> render_click()

    html = render(liveview)
    assert html =~ "Issuer"
    assert html =~ "Serial"
    assert html =~ "Version"
    assert html =~ "Public Key"
    assert html =~ "Expires In"
  end

  test "GET /applications certificate modal displays certificate values from fixture", %{
    conn: conn
  } do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    liveview |> element("#show-tls-certificate-id") |> render_click()

    # Values should match what FixtureStatus.deployex() sets on the tls field
    deployex = FixtureStatus.deployex()
    cert = deployex.tls

    html = render(liveview)
    assert html =~ cert.issuer
    assert html =~ to_string(cert.serial)
    assert html =~ to_string(cert.version)
    assert html =~ cert.public_key_type
  end

  test "GET /applications certificate modal displays covered domains", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    liveview |> element("#show-tls-certificate-id") |> render_click()

    deployex = FixtureStatus.deployex()

    html = render(liveview)
    assert html =~ "Covered Domains"
    Enum.each(deployex.tls.domains, &assert(html =~ &1))
  end

  test "GET /applications certificate modal highlights expiry when within 30 days", %{conn: conn} do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    expiring_cert = FixtureStatus.certificate(%{expires_in_days: 10})

    new_state = [
      FixtureStatus.deployex(%{tls: expiring_cert}),
      FixtureStatus.application()
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    liveview |> element("#show-tls-certificate-id") |> render_click()

    html = render(liveview)
    assert html =~ "10 days"
    assert html =~ "text-error"
    assert html =~ "border-error/50"
  end

  test "GET /applications certificate modal does not highlight expiry when more than 30 days", %{
    conn: conn
  } do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    assert html =~ "bg-success/10 border-success/20 text-success hover:bg-success/20"
  end

  test "GET /applications certificate modal does highlight expiry when less than 30 days", %{
    conn: conn
  } do
    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         %{tls: FixtureStatus.certificate(%{expires_in: 10})}
         |> FixtureStatus.config_by_app()
         |> FixtureStatus.deployex(),
         FixtureStatus.application()
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, _liveview, html} = live(conn, ~p"/applications")

    assert html =~ "bg-error/10 border-error/20 text-error hover:bg-error/20"
  end

  test "GET /applications certificate modal closes on cancel button click", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    liveview |> element("#show-tls-certificate-id") |> render_click()
    assert liveview |> element("#certificate-modal") |> has_element?()

    liveview |> element(".modal-action .btn") |> render_click()

    refute liveview |> element("#certificate-modal") |> has_element?()
  end

  test "GET /applications certificate modal closes on backdrop click", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    liveview |> element("#show-tls-certificate-id") |> render_click()
    assert liveview |> element("#certificate-modal") |> has_element?()

    liveview |> element(".modal-backdrop") |> render_click()

    refute liveview |> element("#certificate-modal") |> has_element?()
  end

  test "GET /applications certificate modal is not shown when TLS is not supported", %{
    conn: conn
  } do
    topic = "test-topic"

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> Phoenix.PubSub.subscribe(Deployer.PubSub, topic) end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    new_state = [
      %{tls: nil} |> FixtureStatus.config_by_app() |> FixtureStatus.deployex(),
      FixtureStatus.application()
    ]

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      topic,
      {:monitoring_app_updated, Node.self(), new_state}
    )

    refute liveview |> element("#show-tls-certificate-id") |> has_element?()
    refute liveview |> element("#certificate-modal") |> has_element?()
  end
end
