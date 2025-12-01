defmodule DeployexWeb.HotUpgrade.GithubTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import Mox
  import Mock

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  describe "github download" do
    test "switches to github upload method", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      html =
        live
        |> element("a", "GitHub URL")
        |> render_click()

      assert html =~ "Download from GitHub"
      assert html =~ "GitHub Artifact URL"
      assert html =~ "GitHub Token (optional)"

      %{socket: socket} = :sys.get_state(live.pid)
      assert socket.assigns.upload_method == :github
    end

    test "switches back to file upload method", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      live
      |> element("a", "GitHub URL")
      |> render_click()

      html =
        live
        |> element("a", "Upload File")
        |> render_click()

      assert html =~ "Upload Hot Upgrade Release"
      assert html =~ "Drop your .tar.gz file here or"

      %{socket: socket} = :sys.get_state(live.pid)
      assert socket.assigns.upload_method == :file
    end

    test "updates github form fields", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      live
      |> element("a", "GitHub URL")
      |> render_click()

      url = "https://github.com/user/repo/actions/runs/123/artifacts/456"
      token = "ghp_test_token_12345"

      live
      |> form("#github-download-form", %{
        "github_url" => url,
        "github_token" => token
      })
      |> render_change()

      %{socket: socket} = :sys.get_state(live.pid)
      assert socket.assigns.form.params["github_url"] == url
      assert socket.assigns.form.params["github_token"] == token
    end

    test "initiates github download", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      with_mock Deployer.Github, [:passthrough],
        download_artifact: fn url, token ->
          send(test_pid, {:download_started, url, token})
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        live
        |> element("a", "GitHub URL")
        |> render_click()

        url = "https://github.com/user/repo/actions/runs/123/artifacts/456"
        token = "ghp_test_token"

        live
        |> form("#github-download-form", %{
          "github_url" => url,
          "github_token" => token
        })
        |> render_change()

        html =
          live
          |> element("#github-download-form")
          |> render_submit()

        assert_receive {:download_started, ^url, ^token}, 1_000

        %{socket: socket} = :sys.get_state(live.pid)
        assert socket.assigns.github.download_status == :downloading
        assert html =~ "Downloading from GitHub..."
      end
    end

    test "shows download progress", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      with_mock Deployer.Github, [:passthrough],
        download_artifact: fn _url, _token ->
          send(test_pid, :download_started)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        live
        |> element("a", "GitHub URL")
        |> render_click()

        url = "https://github.com/user/repo/actions/runs/123/artifacts/456"

        live
        |> form("#github-download-form", %{"github_url" => url, "github_token" => ""})
        |> render_change()

        live
        |> element("#github-download-form")
        |> render_submit()

        assert_receive :download_started, 1_000

        # Simulate progress updates
        send(live.pid, {:github_download_artifact, Node.self(), %{}, {:downloading, 25}})
        html = render(live)
        assert html =~ "25%"

        send(live.pid, {:github_download_artifact, Node.self(), %{}, {:downloading, 50}})
        html = render(live)
        assert html =~ "50%"

        send(live.pid, {:github_download_artifact, Node.self(), %{}, {:downloading, 75}})
        html = render(live)
        assert html =~ "75%"
      end
    end

    test "cancels github download", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      with_mock Deployer.Github, [:passthrough],
        download_artifact: fn _url, _token ->
          send(test_pid, :download_started)
          :ok
        end,
        stop_download_artifact: fn url ->
          send(test_pid, {:download_cancelled, url})
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        live
        |> element("a", "GitHub URL")
        |> render_click()

        url = "https://github.com/user/repo/actions/runs/123/artifacts/456"

        live
        |> form("#github-download-form", %{"github_url" => url, "github_token" => ""})
        |> render_change()

        live
        |> element("#github-download-form")
        |> render_submit()

        assert_receive :download_started, 1_000

        live
        |> element("button", "Cancel")
        |> render_click()

        assert_receive {:download_cancelled, ^url}, 1_000

        %{socket: socket} = :sys.get_state(live.pid)
        assert socket.assigns.github.download_status == nil
        assert socket.assigns.github.download_progress == 0
      end
    end

    test "handles successful github download completion", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mocks([
        {Deployer.HotUpgrade, [:passthrough],
         [
           deployex_check: fn _path -> {:ok, check_data} end
         ]},
        {Deployer.Github, [:passthrough],
         [
           download_artifact: fn _url, _token ->
             send(test_pid, :download_started)
             :ok
           end
         ]}
      ]) do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        live
        |> element("a", "GitHub URL")
        |> render_click()

        url = "https://github.com/user/repo/actions/runs/123/artifacts/456"

        live
        |> form("#github-download-form", %{"github_url" => url, "github_token" => ""})
        |> render_change()

        live
        |> element("#github-download-form")
        |> render_submit()

        assert_receive :download_started, 1_000

        # Create a temporary file to simulate the downloaded artifact
        artifact_name = "deployex-2.0.0.tar.gz"
        artifact_path = Path.join(System.tmp_dir!(), artifact_name)
        File.write!(artifact_path, "fake content")

        send(
          live.pid,
          {:github_download_artifact, Node.self(),
           %{artifact_path: artifact_path, artifact_name: artifact_name}, :ok}
        )

        html = render(live)

        assert html =~ "Uploaded release"
        assert html =~ check_data.name
        assert html =~ check_data.to_version

        %{socket: socket} = :sys.get_state(live.pid)
        assert socket.assigns.github.download_status == nil
        assert socket.assigns.downloaded_release != nil
        assert socket.assigns.downloaded_release.filename == artifact_name

        # Cleanup
        File.rm(artifact_path)
      end
    end

    test "handles github download completion with invalid file", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      assert capture_log(fn ->
               with_mock Deployer.Github, [:passthrough],
                 download_artifact: fn _url, _token ->
                   send(test_pid, :download_started)
                   :ok
                 end do
                 {:ok, live, _html} = live(conn, ~p"/hotupgrade")

                 live
                 |> element("a", "GitHub URL")
                 |> render_click()

                 url = "https://github.com/user/repo/actions/runs/123/artifacts/456"

                 live
                 |> form("#github-download-form", %{"github_url" => url, "github_token" => ""})
                 |> render_change()

                 live
                 |> element("#github-download-form")
                 |> render_submit()

                 assert_receive :download_started, 1_000

                 # Simulate download of invalid file (not .tar.gz)
                 artifact_name = "deployex-2.0.0.zip"
                 artifact_path = Path.join(System.tmp_dir!(), artifact_name)
                 File.write!(artifact_path, "fake content")

                 send(
                   live.pid,
                   {:github_download_artifact, Node.self(),
                    %{artifact_path: artifact_path, artifact_name: artifact_name}, :ok}
                 )

                 html = render(live)

                 assert html =~ "not a .tar.gz file"

                 %{socket: socket} = :sys.get_state(live.pid)
                 assert socket.assigns.downloaded_release == nil

                 # Cleanup
                 File.rm(artifact_path)
               end
             end) =~ "Error while handling file: deployex-2.0.0.zip, reason:  not a .tar.gz file"
    end

    test "handles github download completion with check error", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      assert capture_log(fn ->
               with_mocks([
                 {Deployer.HotUpgrade, [:passthrough],
                  [
                    deployex_check: fn _path -> {:error, :invalid} end
                  ]},
                 {Deployer.Github, [:passthrough],
                  [
                    download_artifact: fn _url, _token ->
                      send(test_pid, :download_started)
                      :ok
                    end
                  ]}
               ]) do
                 {:ok, live, _html} = live(conn, ~p"/hotupgrade")

                 live
                 |> element("a", "GitHub URL")
                 |> render_click()

                 url = "https://github.com/user/repo/actions/runs/123/artifacts/456"

                 live
                 |> form("#github-download-form", %{"github_url" => url, "github_token" => ""})
                 |> render_change()

                 live
                 |> element("#github-download-form")
                 |> render_submit()

                 assert_receive :download_started, 1_000

                 artifact_name = "deployex-2.0.0.tar.gz"
                 artifact_path = Path.join(System.tmp_dir!(), artifact_name)
                 File.write!(artifact_path, "fake content")

                 send(
                   live.pid,
                   {:github_download_artifact, Node.self(),
                    %{artifact_path: artifact_path, artifact_name: artifact_name}, :ok}
                 )

                 html = render(live)

                 assert html =~ "invalid release"

                 %{socket: socket} = :sys.get_state(live.pid)
                 refute socket.assigns.downloaded_release

                 # Cleanup
                 File.rm(artifact_path)
               end
             end) =~ "Error while handling file: deployex-2.0.0.tar.gz, reason: invalid release"
    end

    test "ignores github download events from other nodes", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      with_mock Deployer.Github, [:passthrough],
        download_artifact: fn _url, _token ->
          send(test_pid, :download_started)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        live
        |> element("a", "GitHub URL")
        |> render_click()

        url = "https://github.com/user/repo/actions/runs/123/artifacts/456"

        live
        |> form("#github-download-form", %{"github_url" => url, "github_token" => ""})
        |> render_change()

        live
        |> element("#github-download-form")
        |> render_submit()

        assert_receive :download_started, 1_000

        # Send event from different node
        send(
          live.pid,
          {:github_download_artifact, :other_node@localhost, %{}, {:downloading, 50}}
        )

        %{socket: socket} = :sys.get_state(live.pid)
        # Progress should still be 0 since event was from different node
        assert socket.assigns.github.download_progress == 0
      end
    end

    test "ignores github download events when not downloading", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      # Send download progress event without initiating download
      send(live.pid, {:github_download_artifact, Node.self(), %{}, {:downloading, 50}})

      %{socket: socket} = :sys.get_state(live.pid)
      assert socket.assigns.github.download_status == nil
      assert socket.assigns.github.download_progress == 0
    end

    test "disables download button while downloading", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      with_mock Deployer.Github, [:passthrough],
        download_artifact: fn _url, _token ->
          send(test_pid, :download_started)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        live
        |> element("a", "GitHub URL")
        |> render_click()

        url = "https://github.com/user/repo/actions/runs/123/artifacts/456"

        live
        |> form("#github-download-form", %{"github_url" => url, "github_token" => ""})
        |> render_change()

        html =
          live
          |> element("#github-download-form")
          |> render_submit()

        assert_receive :download_started, 1_000
        assert html =~ "disabled"
        assert html =~ "Downloading from GitHub..."
      end
    end

    test "download button not shown when URL is empty", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      html =
        live
        |> element("a", "GitHub URL")
        |> render_click()

      refute html =~ "Download Release"
    end

    test "Cancel download when not downloading", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, _live, _html} = live(conn, ~p"/hotupgrade")

      assert {:noreply, "nosocket"} =
               DeployexWeb.HotUpgradeLive.handle_event("cancel-github-download", nil, "nosocket")
    end

    test "shows download button when URL is provided", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      live
      |> element("a", "GitHub URL")
      |> render_click()

      html =
        live
        |> form("#github-download-form", %{
          "github_url" => "https://github.com/user/repo/actions/runs/123/artifacts/456",
          "github_token" => ""
        })
        |> render_change()

      assert html =~ "Download Release"
    end
  end

  # Helper functions

  defp create_check_data do
    %Deployer.HotUpgrade.Check{
      sname: "deployex",
      name: "deployex",
      language: "elixir",
      download_path: "/tmp/deployex-1.0.0.tar.gz",
      current_path: "",
      new_path: "",
      from_version: "1.0.0",
      to_version: "1.1.0"
    }
  end
end
