defmodule DeployexWeb.ProcessLabelTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Cache
  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias DeployexWeb.ProcessLabel

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  defp label_of(pid) do
    {:dictionary, dictionary} = Process.info(pid, :dictionary)
    Keyword.get(dictionary, :"$process_label")
  end

  describe "on_mount/4" do
    test "labels a connected LiveView with its view and the signed-in user" do
      socket = %Phoenix.LiveView.Socket{
        transport_pid: self(),
        view: DeployexWeb.ApplicationsLive,
        assigns: %{current_user: %{username: "admin"}}
      }

      assert {:cont, ^socket} = ProcessLabel.on_mount(:default, %{}, %{}, socket)

      assert label_of(self()) == {:live_view, DeployexWeb.ApplicationsLive, "admin"}
    end

    test "omits the user when nobody is signed in" do
      socket = %Phoenix.LiveView.Socket{
        transport_pid: self(),
        view: DeployexWeb.UserLoginLive,
        assigns: %{}
      }

      assert {:cont, ^socket} = ProcessLabel.on_mount(:default, %{}, %{}, socket)

      assert label_of(self()) == {:live_view, DeployexWeb.UserLoginLive}
    end

    # The hook also runs in the short-lived HTTP process that renders the static page; labelling
    # that one would name a request handler after a LiveView.
    test "does not label the disconnected (static render) process" do
      socket = %Phoenix.LiveView.Socket{
        transport_pid: nil,
        view: DeployexWeb.ApplicationsLive,
        assigns: %{current_user: %{username: "admin"}}
      }

      # ExUnit labels the test process itself, so this has to be asserted from a fresh process
      # that starts out with no label at all.
      test_pid = self()

      spawn(fn ->
        assert {:cont, ^socket} = ProcessLabel.on_mount(:default, %{}, %{}, socket)
        send(test_pid, {:label, label_of(self())})
      end)

      assert_receive {:label, nil}
    end
  end

  @tag :capture_log
  test "a real LiveView process carries the label", %{conn: conn, user: user} do
    Cache.UiSettings.set(%Cache.UiSettings{})

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert label_of(index_live.pid) == {:live_view, DeployexWeb.ApplicationsLive, user.username}
  end
end
