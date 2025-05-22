defmodule DeployexWeb.Applications.VersionsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias DeployexWeb.Helper
  alias Foundation.Catalog

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /versions full list", %{conn: conn} do
    name = "test_app"
    %{sname: sname_1, suffix: suffix_1} = name |> Catalog.create_sname() |> Catalog.node_info()
    %{sname: sname_2, suffix: suffix_2} = name |> Catalog.create_sname() |> Catalog.node_info()

    sname_1_version =
      FixtureStatus.version(%{
        version: "10.11.12",
        sname: sname_1,
        deployment: :full_deployment
      })

    sname_2_version =
      FixtureStatus.version(%{
        version: "10.11.13",
        sname: sname_2,
        deployment: :hot_upgrade
      })

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{sname: sname_1, name: name}),
         FixtureStatus.application(%{sname: sname_2, name: name})
       ]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> [sname_1_version, sname_2_version] end)
    |> stub(:history_version_list, fn
      ^sname_1 -> [sname_1_version]
      ^sname_2 -> [sname_2_version]
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    html = index_live |> element("#app-versions-deployex") |> render_click()

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.12"
    assert html =~ :full_deployment |> to_string
    assert html =~ suffix_1

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.13"
    assert html =~ :hot_upgrade |> to_string
    assert html =~ suffix_2

    refute html =~ "0.3456702894.2351693834"
  end

  test "GET /versions list by instance", %{conn: conn} do
    name = "test_app"
    name_id = Helper.normalize_id(name)
    %{sname: sname, suffix: suffix} = name |> Catalog.create_sname() |> Catalog.node_info()

    sname_v1 =
      FixtureStatus.version(%{
        version: "10.11.16",
        name: name,
        sname: sname,
        deployment: :full_deployment
      })

    sname_v2 =
      FixtureStatus.version(%{
        version: "10.11.17",
        name: name,
        sname: sname,
        deployment: :hot_upgrade
      })

    Deployer.StatusMock
    |> expect(:monitoring, fn ->
      {:ok, [FixtureStatus.deployex(), FixtureStatus.application(%{sname: sname, name: name})]}
    end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn -> [sname_v1, sname_v2] end)
    |> stub(:history_version_list, fn ^sname -> [sname_v1, sname_v2] end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    html = index_live |> element("#app-versions-#{name_id}-#{suffix}") |> render_click()

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.16"
    assert html =~ :full_deployment |> to_string
    assert html =~ suffix

    assert html =~ "Monitored App version history"
    assert html =~ "10.11.17"
    assert html =~ :hot_upgrade |> to_string
    assert html =~ suffix

    refute html =~ "0.3456702894.2351693834"
  end
end
