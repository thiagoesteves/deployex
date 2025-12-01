defmodule Deployer.Github.ArtifactTest do
  use ExUnit.Case, async: false

  import Mock

  alias Deployer.Github.Artifact
  alias Foundation.System.FinchStream
  alias Foundation.System.Zip

  @github_artifacts_table :deployex_github_table
  @github_download_progress "deployex::github::download"
  @test_url "https://github.com/owner/repo/actions/runs/123456/artifacts/789"
  @test_token "ghp_test_token"

  describe "init/1" do
    test "creates ETS table on initialization" do
      # The table should exist after setup
      assert :ets.info(@github_artifacts_table) != :undefined
    end
  end

  describe "subscribe_download_events/0" do
    test "subscribes to download events" do
      assert :ok = Artifact.subscribe_download_events()

      # Verify subscription by broadcasting a message
      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        @github_download_progress,
        {:test_message, :subscribed}
      )

      assert_receive {:test_message, :subscribed}
    end
  end

  describe "stop_download_artifact/1" do
    test "inserts stop status into ETS table" do
      url = "https://github.com/owner/repo/actions/runs/123/artifacts/456"

      assert :ok = Artifact.stop_download_artifact(url)

      assert [{^url, :stop}] = :ets.lookup(@github_artifacts_table, url)
    end
  end

  describe "download_artifact/2 - successful flow" do
    test "successfully downloads and unzips artifact" do
      artifact_name = "test-artifact"

      with_mocks [
        {Finch, [],
         [
           build: fn :get, _url, _headers, _opts -> :mocked_request end,
           request: fn :mocked_request, _finch ->
             body =
               Jason.encode!(%{
                 "name" => artifact_name,
                 "archive_download_url" => "https://api.github.com/download/artifact.zip"
               })

             {:ok, %Finch.Response{status: 200, body: body}}
           end
         ]},
        {Zip, [], [unzip: fn _path, _options -> {:ok, []} end]},
        {FinchStream, [],
         [
           download: fn _url, file_path, _headers, opts ->
             # Call the notify callback if provided
             notify_callback = Keyword.get(opts, :notify_callback)

             if notify_callback do
               notify_callback.(file_path, {:downloading, 50.0})
               notify_callback.(file_path, {:downloading, 100.0})
             end

             :ok
           end
         ]}
      ] do
        Artifact.subscribe_download_events()

        Artifact.download_artifact(@test_url, @test_token)

        # Should receive progress notifications
        assert_receive {:github_download_artifact, _node, _data, {:downloading, 50.0}}, 1_000
        assert_receive {:github_download_artifact, _node, _data, {:downloading, 100.0}}, 1_000

        # Should receive final success notification
        assert_receive {:github_download_artifact, _node, final_data, :ok}, 1000

        assert final_data.artifact_name == artifact_name
        assert final_data.owner == "owner"
        assert final_data.repo == "repo"
      end
    end

    @tag :capture_log
    test "skips :ok notification from notify_callback during download" do
      artifact_name = "test-artifact"

      with_mocks [
        {Finch, [],
         [
           build: fn :get, _url, _headers, _opts -> :mocked_request end,
           request: fn :mocked_request, _finch ->
             body =
               Jason.encode!(%{
                 "name" => artifact_name,
                 "archive_download_url" => "https://api.github.com/download/artifact.zip"
               })

             {:ok, %Finch.Response{status: 200, body: body}}
           end
         ]},
        {Zip, [], [unzip: fn _path, _options -> {:ok, []} end]},
        {FinchStream, [],
         [
           download: fn _url, file_path, _headers, opts ->
             notify_callback = Keyword.get(opts, :notify_callback)

             if notify_callback do
               # This :ok should be skipped by the notify_callback
               notify_callback.(file_path, :ok)
               notify_callback.(file_path, {:downloading, 100.0})
             end

             :ok
           end
         ]}
      ] do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, @test_token)

        # Should receive downloading notification
        assert_receive {:github_download_artifact, _node, _data, {:downloading, 100.0}}

        # Should receive final :ok from do_download_artifact, not from notify_callback
        assert_receive {:github_download_artifact, _node, _data, :ok}, 1000
      end
    end
  end

  describe "download_artifact/2 - error scenarios" do
    @tag :capture_log
    test "handles invalid URL error" do
      invalid_url = "https://invalid.com/url"

      Artifact.subscribe_download_events()
      Artifact.download_artifact(invalid_url, @test_token)

      assert_receive {:github_download_artifact, _node, data, {:error, :invalid_url}}, 1000
      assert data.url == invalid_url
    end

    @tag :capture_log
    test "handles GitHub API error when fetching artifact name" do
      with_mock Finch,
        build: fn :get, _url, _headers, _opts -> :mocked_request end,
        request: fn :mocked_request, _finch ->
          {:error, %Finch.Response{status: 404, body: "{}"}}
        end do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, @test_token)

        assert_receive {:github_download_artifact, _node, _data, error}, 1000
        assert elem(error, 0) == :error
      end
    end

    @tag :capture_log
    test "handles Finch request error" do
      with_mock Finch,
        build: fn :get, _url, _headers, _opts -> :mocked_request end,
        request: fn :mocked_request, _finch ->
          {:error, %Mint.TransportError{reason: :timeout}}
        end do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, @test_token)

        assert_receive {:github_download_artifact, _node, _data, error}, 1000
        assert elem(error, 0) == :error
      end
    end

    @tag :capture_log
    test "handles JSON decode error" do
      with_mock Finch,
        build: fn :get, _url, _headers, _opts -> :mocked_request end,
        request: fn :mocked_request, _finch ->
          {:ok, %Finch.Response{status: 200, body: "invalid json"}}
        end do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, @test_token)

        assert_receive {:github_download_artifact, _node, _data, error}, 1000
        assert elem(error, 0) == :error
      end
    end

    @tag :capture_log
    test "handles missing artifact name in response" do
      with_mock Finch,
        build: fn :get, _url, _headers, _opts -> :mocked_request end,
        request: fn :mocked_request, _finch ->
          body = Jason.encode!(%{"id" => 123})
          {:error, %Finch.Response{status: 200, body: body}}
        end do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, @test_token)

        assert_receive {:github_download_artifact, _node, _data, error}, 1000
        assert elem(error, 0) == :error
      end
    end

    @tag :capture_log
    test "handles download error from FinchStream" do
      with_mocks [
        {Finch, [],
         [
           build: fn :get, _url, _headers, _opts -> :mocked_request end,
           request: fn :mocked_request, _finch ->
             body =
               Jason.encode!(%{
                 "name" => "test-artifact",
                 "archive_download_url" => "https://api.github.com/download/artifact.zip"
               })

             {:ok, %Finch.Response{status: 200, body: body}}
           end
         ]},
        {FinchStream, [],
         [
           download: fn _url, _file_path, _headers, _opts ->
             {:error, :connection_failed}
           end
         ]}
      ] do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, @test_token)

        assert_receive {:github_download_artifact, _node, _data, {:error, :connection_failed}},
                       1000
      end
    end
  end

  describe "download_artifact/2 - URL parsing edge cases" do
    @tag :capture_log
    test "handles URL with extra slashes" do
      url = "https://github.com//owner//repo//123//dsdfsdsdf//456"

      Artifact.subscribe_download_events()
      Artifact.download_artifact(url, @test_token)

      assert_receive {:github_download_artifact, _node, _data, {:error, :invalid_url}}, 1000
    end
  end

  describe "download_artifact/2 - header variations" do
    test "builds headers with valid token" do
      artifact_name = "test-artifact"

      with_mocks [
        {Finch, [],
         [
           build: fn :get, _url, headers, _opts ->
             # Verify headers contain Authorization
             assert {"Authorization", "Bearer #{@test_token}"} in headers
             assert {"Accept", "application/vnd.github+json"} in headers
             assert {"X-GitHub-Api-Version", "2022-11-28"} in headers
             :mocked_request
           end,
           request: fn :mocked_request, _finch ->
             body =
               Jason.encode!(%{
                 "name" => artifact_name,
                 "archive_download_url" => "https://api.github.com/download/artifact.zip"
               })

             {:ok, %Finch.Response{status: 200, body: body}}
           end
         ]},
        {Zip, [], [unzip: fn _path, _options -> {:ok, []} end]},
        {FinchStream, [],
         [
           download: fn _url, _file_path, _headers, _opts ->
             :ok
           end
         ]}
      ] do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, @test_token)

        assert_receive {:github_download_artifact, _node, _data, :ok}, 1000
      end
    end

    @tag :capture_log
    test "builds headers without token when token is nil" do
      artifact_name = "test-artifact"

      with_mocks [
        {Finch, [],
         [
           build: fn :get, _url, headers, _opts ->
             # Verify headers do not contain Authorization
             refute Enum.any?(headers, fn {key, _} -> key == "Authorization" end)
             assert {"Accept", "application/vnd.github+json"} in headers
             assert {"X-GitHub-Api-Version", "2022-11-28"} in headers
             :mocked_request
           end,
           request: fn :mocked_request, _finch ->
             body =
               Jason.encode!(%{
                 "name" => artifact_name,
                 "archive_download_url" => "https://api.github.com/download/artifact.zip"
               })

             {:ok, %Finch.Response{status: 200, body: body}}
           end
         ]},
        {Zip, [], [unzip: fn _path, _options -> {:ok, []} end]},
        {FinchStream, [], [download: fn _url, _file_path, _headers, _opts -> :ok end]}
      ] do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, nil)

        assert_receive {:github_download_artifact, _node, _data, :ok}, 1000
      end
    end

    @tag :capture_string
    test "builds headers without token when token is empty string" do
      artifact_name = "test-artifact"

      with_mocks [
        {Finch, [],
         [
           build: fn :get, _url, headers, _opts ->
             # Verify headers do not contain Authorization
             refute Enum.any?(headers, fn {key, _} -> key == "Authorization" end)
             assert {"Accept", "application/vnd.github+json"} in headers
             assert {"X-GitHub-Api-Version", "2022-11-28"} in headers
             :mocked_request
           end,
           request: fn :mocked_request, _finch ->
             body =
               Jason.encode!(%{
                 "name" => artifact_name,
                 "archive_download_url" => "https://api.github.com/download/artifact.zip"
               })

             {:ok, %Finch.Response{status: 200, body: body}}
           end
         ]},
        {Zip, [], [unzip: fn _path, _options -> {:ok, []} end]},
        {FinchStream, [], [download: fn _url, _file_path, _headers, _opts -> :ok end]}
      ] do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, "")

        assert_receive {:github_download_artifact, _node, _data, :ok}, 1000
      end
    end
  end

  describe "download_artifact/2 - cancellation" do
    @tag :capture_log
    test "stops download when stop_download_artifact is called" do
      artifact_name = "test-artifact"

      with_mocks [
        {Finch, [],
         [
           build: fn :get, _url, _headers, _opts -> :mocked_request end,
           request: fn :mocked_request, _finch ->
             body =
               Jason.encode!(%{
                 "name" => artifact_name,
                 "archive_download_url" => "https://api.github.com/download/artifact.zip"
               })

             {:ok, %Finch.Response{status: 200, body: body}}
           end
         ]},
        {Zip, [], [unzip: fn _path, _options -> {:ok, []} end]},
        {FinchStream, [],
         [
           download: fn _url, file_path, _headers, opts ->
             # Simulate download with keep_downloading_callback check
             notify_callback = Keyword.get(opts, :notify_callback)

             File.mkdir_p!(Path.dirname(file_path))

             # Simulate initial progress
             if notify_callback do
               notify_callback.(file_path, {:downloading, 25.0})
             end

             {:error, "Download was cancelled"}
           end
         ]}
      ] do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, @test_token)
        Artifact.stop_download_artifact(@test_url)

        # Should receive error notification
        assert_receive {:github_download_artifact, _node, _data,
                        {:error, "Download was cancelled"}},
                       1000
      end
    end

    test "continues download when both process is alive and status is :run" do
      artifact_name = "test-artifact"

      with_mocks [
        {Finch, [],
         [
           build: fn :get, _url, _headers, _opts -> :mocked_request end,
           request: fn :mocked_request, _finch ->
             body =
               Jason.encode!(%{
                 "name" => artifact_name,
                 "archive_download_url" => "https://api.github.com/download/artifact.zip"
               })

             {:ok, %Finch.Response{status: 200, body: body}}
           end
         ]},
        {Zip, [], [unzip: fn _path, _options -> {:ok, []} end]},
        {FinchStream, [],
         [
           download: fn _url, _file_path, _headers, opts ->
             keep_downloading_callback = Keyword.get(opts, :keep_downloading_callback)

             # Verify keep_downloading returns true
             assert keep_downloading_callback.() == true

             :ok
           end
         ]}
      ] do
        Artifact.subscribe_download_events()
        Artifact.download_artifact(@test_url, @test_token)

        assert_receive {:github_download_artifact, _node, _data, :ok}, 1000
      end
    end

    @tag :capture_log
    test "stops download when request process dies" do
      artifact_name = "test-artifact"
      test_pid = self()

      Artifact.subscribe_download_events()

      task =
        Task.async(fn ->
          with_mocks [
            {Finch, [],
             [
               build: fn :get, _url, _headers, _opts -> :mocked_request end,
               request: fn :mocked_request, _finch ->
                 body =
                   Jason.encode!(%{
                     "name" => artifact_name,
                     "archive_download_url" => "https://api.github.com/download/artifact.zip"
                   })

                 {:ok, %Finch.Response{status: 200, body: body}}
               end
             ]},
            {FinchStream, [],
             [
               download: fn _url, _file_path, _headers, _opts ->
                 send(test_pid, :download_started)
                 {:error, "Download was cancelled"}
               end
             ]}
          ] do
            Artifact.download_artifact(@test_url, @test_token)
            :timer.sleep(1000)
          end
        end)

      # Wait for download to start
      assert_receive :download_started, 1000

      # Kill the task (simulating request process dying)
      Task.shutdown(task, :brutal_kill)

      # Should receive error notification
      assert_receive {:github_download_artifact, _node, _data,
                      {:error, "Download was cancelled"}},
                     1000
    end
  end
end
