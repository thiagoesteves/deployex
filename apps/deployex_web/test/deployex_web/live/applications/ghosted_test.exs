defmodule DeployexWeb.Applications.GhostedTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias Foundation.Catalog

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  defp ghosted(version, sname) do
    %Catalog.Version{
      version: version,
      sname: sname,
      name: "myelixir",
      deployment: :hot_upgrade,
      inserted_at: ~N[2026-08-11 10:00:00]
    }
  end

  defp monitoring_with_ghosted(name, last_ghosted_version) do
    fn ->
      config = %{
        last_ghosted_version: last_ghosted_version,
        mode: :automatic,
        manual_version: nil,
        versions: []
      }

      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{name: name}, config)
       ]}
    end
  end

  @tag :capture_log
  test "GET /applications lists every ghosted version", %{conn: conn} do
    name = "myelixir"

    Deployer.StatusMock
    |> expect(:monitoring, monitoring_with_ghosted(name, "2.0.0"))
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:ghosted_version_list, fn ^name ->
      [ghosted("2.0.0", "myelixir-abc123"), ghosted("1.5.0", "myelixir-def456")]
    end)

    {:ok, index_live, html} = live(conn, ~p"/applications")

    # the card only shows the last one
    assert html =~ "2.0.0"
    refute html =~ "1.5.0"

    html = index_live |> element("#app-ghosted-#{name}") |> render_click()

    assert html =~ "#{name} ghosted versions"
    assert html =~ "2 ghosted versions"
    assert html =~ "2.0.0"
    assert html =~ "1.5.0"
    assert html =~ "myelixir-def456"
    assert html =~ "Clear All"
  end

  @tag :capture_log
  test "removes a single ghosted version", %{conn: conn} do
    name = "myelixir"
    test_pid = self()

    Deployer.StatusMock
    |> expect(:monitoring, monitoring_with_ghosted(name, "2.0.0"))
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:ghosted_version_list, fn ^name ->
      [ghosted("2.0.0", "myelixir-abc123"), ghosted("1.5.0", "myelixir-def456")]
    end)
    # no engine worker is running for this application, so the stored list is updated
    |> expect(:remove_ghosted_version, 1, fn ^name, "2.0.0" ->
      send(test_pid, {:removed, "2.0.0"})
      {:ok, [ghosted("1.5.0", "myelixir-def456")]}
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    index_live |> element("#app-ghosted-#{name}") |> render_click()

    html = index_live |> element("#ghosted-remove-2-0-0") |> render_click()

    assert_receive {:removed, "2.0.0"}

    # only the removed row goes, the card keeps showing the last ghosted version it was
    # given by the monitoring update
    refute has_element?(index_live, "#ghosted-remove-2-0-0")
    assert has_element?(index_live, "#ghosted-remove-1-5-0")
    assert html =~ "1 ghosted version"
  end

  @tag :capture_log
  test "clears every ghosted version", %{conn: conn} do
    name = "myelixir"
    test_pid = self()

    Deployer.StatusMock
    |> expect(:monitoring, monitoring_with_ghosted(name, "2.0.0"))
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:ghosted_version_list, fn ^name ->
      [ghosted("2.0.0", "myelixir-abc123"), ghosted("1.5.0", "myelixir-def456")]
    end)
    |> expect(:clear_ghosted_versions, 1, fn ^name ->
      send(test_pid, :cleared)
      {:ok, []}
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    index_live |> element("#app-ghosted-#{name}") |> render_click()

    html = index_live |> element("#ghosted-clear-all") |> render_click()

    assert_receive :cleared

    assert html =~ "No ghosted versions"
    refute html =~ "Clear All"
  end

  @tag :capture_log
  test "shows nothing to clear when no version is ghosted", %{conn: conn} do
    name = "myelixir"

    Deployer.StatusMock
    |> expect(:monitoring, monitoring_with_ghosted(name, nil))
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:ghosted_version_list, fn ^name -> [] end)

    {:ok, index_live, html} = live(conn, ~p"/applications")

    # with no ghosted version the card has nothing to open
    assert html =~ "No ghosted versions"
    refute has_element?(index_live, "#app-ghosted-#{name}")
  end
end
