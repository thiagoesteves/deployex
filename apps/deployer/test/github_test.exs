defmodule Deployer.GithubTest do
  use ExUnit.Case, async: false

  import Mock
  import ExUnit.CaptureLog

  alias Deployer.Github.Release

  describe "start_link/1" do
    test "Check the GenServer with default name was started" do
      assert Process.whereis(Release)
    end

    test "starts the GenServer with custom name" do
      custom_name = :test_github_server
      assert {:ok, pid} = Release.start_link(name: custom_name)
      assert Process.whereis(custom_name) == pid
      GenServer.stop(pid)
    end

    test "initializes with fetched github information" do
      custom_name = :test_github_server

      mock_response = build_mock_response()

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/deployex/deployex/releases/latest"
                    },
                    _module ->
          {:ok, %{status: 200, headers: [], body: Jason.encode!(mock_response)}}
        end do
        assert {:ok, pid} = Release.start_link(name: custom_name)

        assert state = Release.latest_release(custom_name)
        assert state.tag_name == "1.0.0"
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
      {:ok, pid} = Release.start_link(update_github_interval: :timer.hours(1), name: custom_name)

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "initializes state with github information" do
      mock_response = build_mock_response()

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/deployex/deployex/releases/latest"
                    },
                    _module ->
          {:ok, %{status: 200, headers: [], body: Jason.encode!(mock_response)}}
        end do
        assert {:ok, state} = Release.init([])
        assert %Release{} = state
        assert state.tag_name == "1.0.0"
      end
    end

    test "initializes with empty struct on error" do
      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/deployex/deployex/releases/latest"
                    },
                    _module ->
          {:error, %{reason: :timeout}}
        end do
        assert {:ok, state} = Release.init([])
        assert %Release{} = state
        assert state.tag_name == ""
      end
    end
  end

  describe "release check turned off" do
    setup do
      previous = Application.get_env(:deployer, Release)
      Application.put_env(:deployer, Release, enabled: false)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:deployer, Release, previous),
          else: Application.delete_env(:deployer, Release)
      end)
    end

    @tag :capture_log
    test "makes no call to GitHub and reports no new release" do
      custom_name = :test_github_server_off

      with_mock Finch, [:passthrough], request: fn _request, _module -> {:error, :called} end do
        {:ok, pid} = Release.start_link(name: custom_name, update_github_interval: 10)

        assert Release.latest_release(custom_name) == %Release{}
        assert :sys.get_state(pid) == %Release{}

        # Longer than the interval, so a timer would have fired by now
        Process.sleep(50)
        assert_not_called(Finch.request(:_, :_))

        GenServer.stop(pid)
      end
    end
  end

  describe "handle_info/2" do
    test "updates state on :updated_github_info message" do
      initial_state = %Release{tag_name: "1.0.0"}
      mock_response = build_mock_response(%{"tag_name" => "2.0.0"})

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/deployex/deployex/releases/latest"
                    },
                    _module ->
          {:ok, %{status: 200, headers: [], body: Jason.encode!(mock_response)}}
        end do
        assert {:noreply, new_state} = Release.handle_info(:updated_github_info, initial_state)
        assert new_state.tag_name == "2.0.0"
        assert new_state.new_release?
      end
    end

    test "preserves state when version doesn't follow semver" do
      initial_state = %Release{tag_name: "1.0.0"}
      mock_response = build_mock_response(%{"tag_name" => "sfsdfsfsdf"})

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/deployex/deployex/releases/latest"
                    },
                    _module ->
          {:ok, %{status: 200, headers: [], body: Jason.encode!(mock_response)}}
        end do
        assert {:noreply, new_state} = Release.handle_info(:updated_github_info, initial_state)
        refute new_state.new_release?
      end
    end

    test "preserves state when update fails" do
      initial_state = %Release{tag_name: "1.0.0", prerelease: false}

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{
                      host: "api.github.com",
                      path: "/repos/deployex/deployex/releases/latest"
                    },
                    _module ->
          {:error, %{reason: :timeout}}
        end do
        capture_log(fn ->
          assert {:noreply, new_state} = Release.handle_info(:updated_github_info, initial_state)
          assert new_state == initial_state
        end)
      end
    end
  end

  test "fetch latest version from default module" do
    assert %Release{} = Release.latest_release()
  end

  test "handles timeout error" do
    previous_state = %Release{tag_name: "v0.9.0"}

    with_mock Finch, [:passthrough],
      request: fn %Finch.Request{
                    host: "api.github.com",
                    path: "/repos/deployex/deployex/releases/latest"
                  },
                  _module ->
        {:error, %{reason: :timeout}}
      end do
      new_state = Release.update_github_info(previous_state)
      assert new_state == previous_state
    end
  end

  test "follows a redirect when the repository has moved" do
    moved_path = "/repositories/796812023/releases/latest"
    mock_response = build_mock_response(%{"tag_name" => "2.0.0"})

    with_mock Finch, [:passthrough],
      request: fn
        %Finch.Request{path: "/repos/deployex/deployex/releases/latest"}, _module ->
          {:ok,
           %{
             status: 301,
             headers: [{"location", "https://api.github.com" <> moved_path}],
             body: ~s({"message":"Moved Permanently"})
           }}

        %Finch.Request{host: "api.github.com", path: ^moved_path}, _module ->
          {:ok, %{status: 200, headers: [], body: Jason.encode!(mock_response)}}
      end do
      new_state = Release.update_github_info(%Release{})
      assert new_state.tag_name == "2.0.0"
      assert new_state.new_release?
    end
  end

  test "keeps previous state when redirects never end" do
    previous_state = %Release{tag_name: "v0.9.0"}

    with_mock Finch, [:passthrough],
      request: fn %Finch.Request{}, _module ->
        {:ok,
         %{
           status: 301,
           headers: [
             {"location", "https://api.github.com/repos/deployex/deployex/releases/latest"}
           ],
           body: ~s({"message":"Moved Permanently"})
         }}
      end do
      assert Release.update_github_info(previous_state) == previous_state
      assert_called_exactly(Finch.request(:_, :_), 4)
    end
  end

  test "keeps previous state on a non-200 response" do
    previous_state = %Release{tag_name: "v0.9.0"}

    with_mock Finch, [:passthrough],
      request: fn %Finch.Request{}, _module ->
        {:ok, %{status: 403, headers: [], body: ~s({"message":"API rate limit exceeded"})}}
      end do
      assert Release.update_github_info(previous_state) == previous_state
    end
  end

  # Helper functions
  defp build_mock_response(overrides \\ %{}) do
    Map.merge(
      %{
        "tag_name" => "1.0.0",
        "prerelease" => false,
        "created_at" => "2024-01-01T10:00:00Z",
        "updated_at" => "2024-01-02T10:00:00Z",
        "published_at" => "2024-01-03T10:00:00Z"
      },
      overrides
    )
  end
end
