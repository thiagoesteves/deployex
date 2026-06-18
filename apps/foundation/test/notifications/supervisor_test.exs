defmodule Foundation.Notifications.SupervisorTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.Notifications.Supervisor, as: NotifSupervisor
  alias Foundation.Yaml

  @webhook_config %Yaml.Notification{
    adapter: Foundation.Notifications.Webhook,
    url: "https://hooks.example.com",
    enabled: true,
    events: [:crash_restart],
    options: %{}
  }

  describe "start_link/1" do
    @tag :capture_log
    test "starts one worker per notification entry in app env" do
      with_mocks([
        {Application, [:passthrough],
         [
           get_env: fn
             :foundation, :notifications, [] -> [@webhook_config, @webhook_config]
             app, key, default -> :meck.passthrough([app, key, default])
           end
         ]}
      ]) do
        {:ok, sup} = NotifSupervisor.start_link(name: :test_notif_sup_two)

        children = Supervisor.which_children(sup)
        assert length(children) == 2

        Supervisor.stop(sup)
      end
    end

    @tag :capture_log
    test "starts with no workers when notifications list is empty" do
      with_mocks([
        {Application, [:passthrough],
         [
           get_env: fn
             :foundation, :notifications, [] -> []
             app, key, default -> :meck.passthrough([app, key, default])
           end
         ]}
      ]) do
        {:ok, sup} = NotifSupervisor.start_link(name: :test_notif_sup_empty)

        assert Supervisor.which_children(sup) == []

        Supervisor.stop(sup)
      end
    end
  end
end
