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
    # the stored list, read back by the component after every change
    |> stub(:ghosted_version_list, fn ^name ->
      Process.get("ghosted", [
        ghosted("2.0.0", "myelixir-abc123"),
        ghosted("1.5.0", "myelixir-def456")
      ])
    end)
    # no engine worker is running for this application, so the stored list is updated
    |> expect(:remove_ghosted_version, 1, fn ^name, "2.0.0" ->
      remaining = [ghosted("1.5.0", "myelixir-def456")]
      Process.put("ghosted", remaining)
      send(test_pid, {:removed, "2.0.0"})
      {:ok, remaining}
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    index_live |> element("#app-ghosted-#{name}") |> render_click()

    html = index_live |> element("#ghosted-remove-2-0-0") |> render_click()

    # nothing happens until the confirmation is accepted
    assert html =~ "Remove Ghosted Version"
    assert html =~ "Remove Version"
    refute_receive {:removed, "2.0.0"}

    index_live |> element("#confirm-button-ghosted") |> render_click()

    assert_receive {:removed, "2.0.0"}

    # only the removed row goes, the card keeps showing the last ghosted version it was
    # given by the monitoring update
    refute has_element?(index_live, "#ghosted-remove-2-0-0")
    assert has_element?(index_live, "#ghosted-remove-1-5-0")
  end

  @tag :capture_log
  test "cancelling the confirmation leaves the list alone", %{conn: conn} do
    name = "myelixir"

    Deployer.StatusMock
    |> expect(:monitoring, monitoring_with_ghosted(name, "2.0.0"))
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:ghosted_version_list, fn ^name -> [ghosted("2.0.0", "myelixir-abc123")] end)
    |> expect(:remove_ghosted_version, 0, fn _name, _version -> {:ok, []} end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    index_live |> element("#app-ghosted-#{name}") |> render_click()
    index_live |> element("#ghosted-remove-2-0-0") |> render_click()

    html = index_live |> element("#cancel-button-ghosted") |> render_click()

    # cancelling goes back to the list it was opened from, not out of it
    refute html =~ "Remove Ghosted Version"
    assert has_element?(index_live, "#ghosted-remove-2-0-0")
  end

  @tag :capture_log
  test "clears every ghosted version", %{conn: conn} do
    name = "myelixir"
    test_pid = self()

    Deployer.StatusMock
    |> expect(:monitoring, monitoring_with_ghosted(name, "2.0.0"))
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:ghosted_version_list, fn ^name ->
      Process.get("ghosted", [
        ghosted("2.0.0", "myelixir-abc123"),
        ghosted("1.5.0", "myelixir-def456")
      ])
    end)
    |> expect(:clear_ghosted_versions, 1, fn ^name ->
      Process.put("ghosted", [])
      send(test_pid, :cleared)
      {:ok, []}
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    index_live |> element("#app-ghosted-#{name}") |> render_click()

    html = index_live |> element("#ghosted-clear-all") |> render_click()

    assert html =~ "Clear Ghosted Versions"
    assert html =~ "Yes, Clear All"
    refute_receive :cleared

    index_live |> element("#danger-button-ghosted") |> render_click()

    assert_receive :cleared

    # send_update is handled after the click returns, so the list is read again on the
    # render that follows
    assert render(index_live) =~ "No ghosted versions"
    refute has_element?(index_live, "#ghosted-clear-all")
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
