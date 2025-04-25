defmodule DeployexWeb.Applications.VersionsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Monitoring
  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /versions full list", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn ->
      [
        FixtureStatus.version(%{
          version: "10.11.12",
          instance: 1,
          deploy_ref: "abc123",
          deployment: :full_deployment
        }),
        FixtureStatus.version(%{
          version: "10.11.13",
          instance: 2,
          deploy_ref: "def456",
          deployment: :hot_upgrade
        })
      ]
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    html = index_live |> element("#app-versions-0") |> render_click()

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.12"
    assert html =~ :full_deployment |> to_string
    assert html =~ "abc123"

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.13"
    assert html =~ :hot_upgrade |> to_string
    assert html =~ "def456"

    refute html =~ "0.3456702894.2351693834"
  end

  test "GET /versions list by instance", %{conn: conn} do
    full_list = [
      FixtureStatus.version(%{
        version: "10.11.16",
        instance: 1,
        deploy_ref: "555555",
        deployment: :full_deployment
      }),
      FixtureStatus.version(%{
        version: "10.11.17",
        instance: 1,
        deploy_ref: "888888",
        deployment: :hot_upgrade
      })
    ]

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> full_list end)
    |> stub(:history_version_list, fn "1" -> full_list end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    html = index_live |> element("#app-versions-1") |> render_click()

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.16"
    assert html =~ :full_deployment |> to_string
    assert html =~ "55555"

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.17"
    assert html =~ :hot_upgrade |> to_string
    assert html =~ "88888"

    refute html =~ "0.3456702894.2351693834"
  end
end
