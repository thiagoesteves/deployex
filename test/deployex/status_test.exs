defmodule Deployex.StatusTest do
  use ExUnit.Case, async: false

  alias Deployex.AppConfig
  alias Deployex.Fixture
  alias Deployex.Status

  setup do
    Fixture.storage_cleanup()

    release = %{
      "version" => "1.0.0",
      "hash" => "ABC",
      "pre_commands" => []
    }

    attrs = [deployment: "full_deployment", deploy_ref: make_ref()]

    Status.set_current_version_map(2, release, attrs)
    Status.set_current_version_map(1, release, attrs)
    Status.set_current_version_map(3, release, attrs)
    Status.set_current_version_map(0, release, attrs)

    %{release: release, attrs: attrs}
  end

  test "current_version / current_version_map" do
    expected_version = "1.0.0"
    expected_hash = "ABC"
    expected_deployment = "full_deployment"

    assert Status.current_version(0) == expected_version
    assert Status.current_version(1) == expected_version
    assert Status.current_version(2) == expected_version
    assert Status.current_version(3) == expected_version

    assert %{
             "deployment" => ^expected_deployment,
             "hash" => ^expected_hash,
             "pre_commands" => [],
             "version" => ^expected_version
           } = Status.current_version_map(0)

    assert %{
             "deployment" => ^expected_deployment,
             "hash" => ^expected_hash,
             "pre_commands" => [],
             "version" => ^expected_version
           } = Status.current_version_map(1)

    assert %{
             "deployment" => ^expected_deployment,
             "hash" => ^expected_hash,
             "pre_commands" => [],
             "version" => ^expected_version
           } = Status.current_version_map(2)

    assert %{
             "deployment" => ^expected_deployment,
             "hash" => ^expected_hash,
             "pre_commands" => [],
             "version" => ^expected_version
           } = Status.current_version_map(3)
  end

  test "listener_topic/0" do
    assert Status.listener_topic() == "monitoring_app_updated"
  end

  test "ghosted_version" do
    assert Enum.empty?(Status.ghosted_version_list())

    version_map = Status.current_version_map(1)

    # Add a version to the ghosted version list
    assert {:ok, _} = Status.add_ghosted_version(version_map)
    assert length(Status.ghosted_version_list()) == 1

    # Try to add the same and check the list didn't increase
    assert {:ok, _} = Status.add_ghosted_version(version_map)
    assert length(Status.ghosted_version_list()) == 1

    # Add another version
    assert {:ok, _} = Status.add_ghosted_version(%{version_map | "version" => "1.1.1"})
    assert length(Status.ghosted_version_list()) == 2
  end

  test "history_version_list" do
    version_list = Status.history_version_list()

    assert length(version_list) == 4

    assert [_] = Status.history_version_list(0)
    assert [_] = Status.history_version_list(1)
    assert [_] = Status.history_version_list(2)
    assert [_] = Status.history_version_list(3)

    assert [_] = Status.history_version_list("0")
    assert [_] = Status.history_version_list("1")
    assert [_] = Status.history_version_list("2")
    assert [_] = Status.history_version_list("3")

    assert %{"instance" => 0} = Enum.at(version_list, 0)
    assert %{"instance" => 2} = Enum.at(version_list, 3)
  end

  test "update monitoring apps" do
    # No info, update needed
    assert {:noreply, monitoring} =
             Deployex.Status.Application.handle_info(:update_apps, %{monitoring: []})

    assert %{
             monitoring: [
               %Deployex.Status{
                 name: "deployex",
                 instance: 0,
                 version: _,
                 otp: :not_connected,
                 tls: :not_supported,
                 last_deployment: nil,
                 supervisor: true,
                 status: :running,
                 restarts: 0,
                 uptime: "now",
                 last_ghosted_version: "-/-"
               },
               %Deployex.Status{
                 name: "testapp",
                 instance: 1,
                 version: "1.0.0",
                 otp: :not_connected,
                 tls: :not_supported,
                 last_deployment: "full_deployment",
                 supervisor: false,
                 status: nil,
                 restarts: nil,
                 uptime: "-/-",
                 last_ghosted_version: nil
               },
               %Deployex.Status{
                 name: "testapp",
                 instance: 2,
                 version: "1.0.0",
                 otp: :not_connected,
                 tls: :not_supported,
                 last_deployment: "full_deployment",
                 supervisor: false,
                 status: nil,
                 restarts: nil,
                 uptime: "-/-",
                 last_ghosted_version: nil
               },
               %Deployex.Status{
                 name: "testapp",
                 instance: 3,
                 version: "1.0.0",
                 otp: :not_connected,
                 tls: :not_supported,
                 last_deployment: "full_deployment",
                 supervisor: false,
                 status: nil,
                 restarts: nil,
                 uptime: "-/-",
                 last_ghosted_version: nil
               }
             ]
           } = monitoring

    # Same info, no updates
    assert {:noreply, ^monitoring} =
             Deployex.Status.Application.handle_info(:update_apps, %{monitoring: monitoring})
  end

  test "update" do
    path = AppConfig.new_path(1)
    assert :ok = Deployex.Status.update(1)
    refute File.exists?(path)
  end

  test "clear_new" do
    assert :ok = Deployex.Status.clear_new(1)
  end
end