defmodule Deployer.GithubTest do
  use ExUnit.Case, async: false

  import Mock
  import ExUnit.CaptureLog

  alias Deployer.Github

  describe "start_link/1" do
    test "Check the GenServer with default name was started" do
      assert Process.whereis(Github)
    end

    test "starts the GenServer with custom name" do
      custom_name = :test_github_server
      assert {:ok, pid} = Github.start_link(name: custom_name)
      assert Process.whereis(custom_name) == pid
      GenServer.stop(pid)
    end

    test "initializes with fetched github information" do
      custom_name = :test_github_server

      mock_response = build_mock_response()

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/thiagoesteves/deployex/releases/latest"
                    },
                    _module ->
          {:ok, %{body: Jason.encode!(mock_response)}}
        end do
        assert {:ok, pid} = Github.start_link(name: custom_name)

        assert {:ok, state} = Github.latest_release(custom_name)
        assert state.tag_name == "v1.0.0"
        assert state.prerelease == false
        assert state.created_at == "2024-01-01T10:00:00Z"

        GenServer.stop(pid)
      end
    end
  end

  describe "init/1" do
    test "sets up periodic update timer" do
      custom_name = :test_github_server

      # Start with a very long interval to avoid automatic updates during test
      {:ok, pid} = Github.start_link(update_github_interval: :timer.hours(1), name: custom_name)

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "initializes state with github information" do
      mock_response = build_mock_response()

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/thiagoesteves/deployex/releases/latest"
                    },
                    _module ->
          {:ok, %{body: Jason.encode!(mock_response)}}
        end do
        assert {:ok, state} = Github.init([])
        assert %Github{} = state
        assert state.tag_name == "v1.0.0"
      end
    end

    test "initializes with empty struct on error" do
      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/thiagoesteves/deployex/releases/latest"
                    },
                    _module ->
          {:error, %{reason: :timeout}}
        end do
        log =
          capture_log(fn ->
            assert {:ok, state} = Github.init([])
            assert %Github{} = state
            assert state.tag_name == ""
          end)

        assert log =~ "Error while trying to get github repo information"
      end
    end
  end

  describe "handle_info/2" do
    test "updates state on :updated_github_info message" do
      initial_state = %Github{tag_name: "v1.0.0"}
      mock_response = build_mock_response(%{"tag_name" => "v2.0.0"})

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/thiagoesteves/deployex/releases/latest"
                    },
                    _module ->
          {:ok, %{body: Jason.encode!(mock_response)}}
        end do
        assert {:noreply, new_state} = Github.handle_info(:updated_github_info, initial_state)
        assert new_state.tag_name == "v2.0.0"
      end
    end

    test "preserves state when update fails" do
      initial_state = %Github{tag_name: "v1.0.0", prerelease: false}

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/thiagoesteves/deployex/releases/latest"
                    },
                    _module ->
          {:error, %{reason: :timeout}}
        end do
        capture_log(fn ->
          assert {:noreply, new_state} = Github.handle_info(:updated_github_info, initial_state)
          assert new_state == initial_state
        end)
      end
    end
  end

  test "fetch latest version from default module" do
    assert {:ok, %Github{}} = Github.latest_release()
  end

  test "handles timeout error" do
    previous_state = %Github{tag_name: "v0.9.0"}

    with_mock Finch, [:passthrough],
      request: fn %Finch.Request{
                    host: "api.github.com",
                    path: "/repos/thiagoesteves/deployex/releases/latest"
                  },
                  _module ->
        {:error, %{reason: :timeout}}
      end do
      log =
        capture_log(fn ->
          new_state = Github.update_github_info(previous_state)
          assert new_state == previous_state
        end)

      assert log =~ "timeout"
    end
  end

  test "handles invalid JSON response" do
    previous_state = %Github{tag_name: "v1.0.0"}

    with_mock Finch, [:passthrough],
      request: fn %Finch.Request{
                    host: "api.github.com",
                    path: "/repos/thiagoesteves/deployex/releases/latest"
                  },
                  _module ->
        {:ok, %{body: "invalid json {"}}
      end do
      assert_raise Jason.DecodeError, fn ->
        Github.update_github_info(previous_state)
      end
    end
  end

  # Helper functions
  defp build_mock_response(overrides \\ %{}) do
    Map.merge(
      %{
        "tag_name" => "v1.0.0",
        "prerelease" => false,
        "created_at" => "2024-01-01T10:00:00Z",
        "updated_at" => "2024-01-02T10:00:00Z",
        "published_at" => "2024-01-03T10:00:00Z"
      },
      overrides
    )
  end
end
