defmodule DeployexWeb.Applications.VersionsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.Fixture.Monitoring

  test "GET /versions full list", %{conn: conn} do
    topic = "topic-version-000"

    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{monitoring: Monitoring.list()}} end)
    |> expect(:listener_topic, fn -> topic end)
    |> expect(:history_version_list, 2, fn ->
      [
        %{
          "version" => "10.11.12",
          "instance" => "1",
          "deployment" => "full_deployment",
          "deploy_ref" => "#Reference<0.3456702894.2351693834.66666>",
          "inserted_at" => NaiveDateTime.utc_now()
        },
        %{
          "version" => "10.11.13",
          "instance" => "2",
          "deployment" => "hot_upgrade",
          "deploy_ref" => "#Reference<0.3456702894.2351693834.99999>",
          "inserted_at" => NaiveDateTime.utc_now()
        }
      ]
    end)

    {:ok, _view, html} = live(conn, ~p"/applications/0/versions")

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.12"
    assert html =~ "full_deployment"
    assert html =~ "66666"

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.13"
    assert html =~ "hot_upgrade"
    assert html =~ "99999"

    refute html =~ "0.3456702894.2351693834"
  end

  test "GET /versions list by instance", %{conn: conn} do
    topic = "topic-version-001"

    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{monitoring: Monitoring.list()}} end)
    |> expect(:listener_topic, fn -> topic end)
    |> expect(:history_version_list, 2, fn "1" ->
      [
        %{
          "version" => "10.11.16",
          "instance" => "1",
          "deployment" => "full_deployment",
          "deploy_ref" => "#Reference<0.3456702894.2351693834.55555>",
          "inserted_at" => NaiveDateTime.utc_now()
        },
        %{
          "version" => "10.11.17",
          "instance" => "1",
          "deployment" => "hot_upgrade",
          "deploy_ref" => "#Reference<0.3456702894.2351693834.88888>",
          "inserted_at" => NaiveDateTime.utc_now()
        }
      ]
    end)

    {:ok, _view, html} = live(conn, ~p"/applications/1/versions")

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.16"
    assert html =~ "full_deployment"
    assert html =~ "55555"

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.17"
    assert html =~ "hot_upgrade"
    assert html =~ "88888"

    refute html =~ "0.3456702894.2351693834"
  end
end
