defmodule DeployexWeb.Applications.VersionsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Nodes, as: FixtureNodes
  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /versions full list", %{conn: conn} do
    node1 = FixtureNodes.test_node("test_app", "abc123")
    node2 = FixtureNodes.test_node("test_app", "abc124")

    node1_version =
      FixtureStatus.version(%{
        version: "10.11.12",
        node: node1,
        deployment: :full_deployment
      })

    node2_version =
      FixtureStatus.version(%{
        version: "10.11.13",
        node: node2,
        deployment: :hot_upgrade
      })

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> [node1_version, node2_version] end)
    |> stub(:history_version_list, fn
      ^node1 -> [node1_version]
      ^node2 -> [node2_version]
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    html = index_live |> element("#app-versions-deployex") |> render_click()

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.12"
    assert html =~ :full_deployment |> to_string
    assert html =~ "abc123"

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.13"
    assert html =~ :hot_upgrade |> to_string
    assert html =~ "abc124"

    refute html =~ "0.3456702894.2351693834"
  end

  test "GET /versions list by instance", %{conn: conn} do
    node = FixtureNodes.test_node("test_app", "abc123")

    node_v1 =
      FixtureStatus.version(%{
        version: "10.11.16",
        node: node,
        deployment: :full_deployment
      })

    node_v2 =
      FixtureStatus.version(%{
        version: "10.11.17",
        node: node,
        deployment: :hot_upgrade
      })

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> [node_v1, node_v2] end)
    |> stub(:history_version_list, fn ^node -> [node_v1, node_v2] end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    html = index_live |> element("#app-versions-test-app-abc123") |> render_click()

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.16"
    assert html =~ :full_deployment |> to_string
    assert html =~ "abc123"

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.17"
    assert html =~ :hot_upgrade |> to_string
    assert html =~ "abc123"

    refute html =~ "0.3456702894.2351693834"
  end
end
