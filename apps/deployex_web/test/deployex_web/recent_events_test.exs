defmodule DeployexWeb.RecentEventsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias DeployexWeb.RecentEvents
  alias Foundation.Notifications.Recent

  setup :log_in_default_user

  defp recent(event, payload),
    do: %Recent{id: 1, at: ~U[2026-10-28 14:20:00Z], event: event, payload: payload}

  describe "item/1" do
    test "describes each event the bell shows" do
      assert [
               %{
                 tone: :ghost,
                 title: "myerlangapp 0.8.2 ghosted",
                 href: "/applications?app=myerlangapp"
               }
             ] =
               RecentEvents.item(
                 recent("version_ghosted", %{name: "myerlangapp", version: "0.8.2", reason: nil})
               )

      assert [%{tone: :error, title: "myapp-abc pre_command failed", detail: "eval Migrate.run"}] =
               RecentEvents.item(
                 recent("pre_command_failed", %{
                   sname: "myapp-abc",
                   name: "myapp",
                   command: "eval Migrate.run"
                 })
               )

      assert [%{tone: :warning, title: "myapp-abc crash restart", detail: "2 crash restarts"}] =
               RecentEvents.item(
                 recent("crash_restart", %{sname: "myapp-abc", crash_restart_count: 2})
               )

      assert [%{detail: "1 crash restart"}] =
               RecentEvents.item(
                 recent("crash_restart", %{sname: "myapp-abc", crash_restart_count: 1})
               )

      assert [%{tone: :warning, title: "myapp-abc process at 81% of the limit"}] =
               RecentEvents.item(
                 recent("watchdog_threshold_warning", %{
                   node: :"myapp-abc@host",
                   type: :process,
                   current_percentage: 81,
                   warning_threshold_percent: 80,
                   action: :warning
                 })
               )

      assert [%{tone: :error, detail: "restarted"}] =
               RecentEvents.item(
                 recent("watchdog_threshold_exceeded", %{
                   node: nil,
                   type: :atom,
                   current_percentage: 95,
                   action: :restart
                 })
               )

      assert [%{detail: "restart is off"}] =
               RecentEvents.item(recent("watchdog_threshold_exceeded", %{action: :no_restart}))

      assert [%{tone: :warning, title: "1 config change pending", detail: "replicas"}] =
               RecentEvents.item(
                 recent("config_changed", %{changes_count: 1, fields: [:replicas]})
               )

      assert [%{tone: :info, title: "2 config changes applied", detail: ""}] =
               RecentEvents.item(
                 recent("config_change_applied", %{changes_count: 2, fields: nil})
               )

      assert [%{tone: :error, title: "TLS certificate renewal failed"}] =
               RecentEvents.item(
                 recent("certificate_failed", %{app_name: "myapp", reason: :timeout})
               )

      assert [%{tone: :info, title: "TLS certificate renewed"}] =
               RecentEvents.item(recent("certificate_renewed", %{app_name: "myapp"}))

      assert [%{tone: :error, title: "myapp-abc deployment failed"}] =
               RecentEvents.item(
                 recent("deployment_complete", %{
                   sname: "myapp-abc",
                   status: :error,
                   message: "boom"
                 })
               )

      assert [%{detail: "lost"}] =
               RecentEvents.item(
                 recent("version_ghosted", %{name: "a", version: "1", reason: "lost"})
               )
    end

    test "skips the events the bell does not show" do
      assert [] = RecentEvents.item(recent("application_ready", %{sname: "myapp-abc"}))
      assert [] = RecentEvents.item(recent("deployment_complete", %{status: :ok}))
      assert [] = RecentEvents.item(recent("watchdog_threshold_warning", %{action: :normalized}))
    end
  end

  @tag :capture_log
  test "the bell on every page follows this host's new events", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/documentation")
    assert html =~ ~s(data-bell="bell")

    send(
      view.pid,
      {:recent_notification,
       recent("crash_restart", %{sname: "myapp-abc", crash_restart_count: 3})}
    )

    html = render(view)
    assert html =~ "myapp-abc crash restart"
    assert html =~ "3 crash restarts"
    assert html =~ ~s(data-bell-item="1")

    # An event the bell does not show changes nothing
    send(view.pid, {:recent_notification, recent("application_ready", %{sname: "myapp-abc"})})
    assert render(view) =~ "myapp-abc crash restart"
  end
end
