defmodule DeployexWeb.HotUpgrade.UploadTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import Mock

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  describe "mount and render" do
    test "GET /hotupgrade renders the hot upgrade manager page", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, _live, html} = live(conn, ~p"/hotupgrade")

      assert html =~ "Hot Upgrade Manager"
      assert html =~ "Upload and apply hot upgrades without downtime"
      assert html =~ "Upload Hot Upgrade Release"
      assert html =~ "Drop your .tar.gz file here or"
    end

    test "initializes with correct default assigns", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      %{socket: socket} = :sys.get_state(live.pid)

      assert socket.assigns.downloaded_release == nil
      assert socket.assigns.applying_upgrade == false
      assert socket.assigns.upgrade_progress == []
      assert socket.assigns.upgrade_state == :init
      assert socket.assigns.total_upgrade_steps == 8
      assert socket.assigns.current_path == "/hotupgrade"
    end
  end

  describe "file upload validation" do
    test "handles validate-upload event", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      assert live
             |> render_hook("validate-upload", %{})
    end

    test "cancels file upload", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      # This would typically be triggered by a user action
      assert live
             |> element("form#upload-form")
             |> render_change(%{})
    end
  end

  describe "release management" do
    @tag :capture_log
    test "remove-release event clears downloaded release", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      Host.CommanderMock
      |> expect(:run, fn _command, _options ->
        {:ok, []}
      end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      download_file(live, "deployex-0.9.0.tar.gz")

      live
      |> element("button", "Remove")
      |> render_click()

      %{socket: socket} = :sys.get_state(live.pid)

      assert socket.assigns.downloaded_release == nil
    end

    test "displays uploaded release information", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-2.0.0.tar.gz"
        download_file(live, filename)

        html = render(live)

        assert html =~ "Uploaded release"
        assert html =~ check_data.name
        assert html =~ check_data.to_version
        assert html =~ filename
      end
    end

    test "displays error when release has error", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      download_file(live, "deployex-0.9.0.gz")

      html = render(live)

      assert html =~ "not a .tar.gz file"
      refute html =~ "Apply Hot Upgrade"
    end

    test "displays error when the release is invalid", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:error, :invalid} end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        download_file(live, "deployex-0.8.0.tar.gz")

        html = render(live)

        assert html =~ "invalid release"
        refute html =~ "Apply Hot Upgrade"
      end
    end
  end

  describe "hot upgrade execution" do
    test "navigates to apply action when Apply button clicked", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-2.0.0.tar.gz"
        download_file(live, filename)

        live
        |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade")
        |> render_click()

        assert_patch(live, ~p"/hotupgrade/apply")
      end
    end

    test "shows confirmation modal on apply action", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-3.0.0.tar.gz"
        download_file(live, filename)

        html =
          live |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade") |> render_click()

        assert html =~ "Hot upgrade"
        assert html =~ "Warning: Destructive Operation"
        assert html =~ "All running application instances will be terminated"
        assert html =~ "Yes, Apply Hot Upgrade"
      end
    end

    test "cancels hot upgrade from confirmation modal", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-3.0.0.tar.gz"
        download_file(live, filename)

        live |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade") |> render_click()

        assert has_element?(live, "#cancel-button-hotupgrade-cancel")

        live
        |> element("#cancel-button-hotupgrade-cancel", "Cancel")
        |> render_click()

        refute has_element?(live, "#cancel-button-hotupgrade-cancel")
      end
    end

    test "executes hot upgrade when confirmed", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end,
        deployex_execute: fn _path, _opts ->
          send(test_pid, :upgrade_executed)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-3.0.0.tar.gz"
        download_file(live, filename)

        live
        |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade")
        |> render_click()

        live
        |> element("#danger-button-hotupgrade-execute", "Yes, Apply Hot Upgrade")
        |> render_click()

        %{socket: socket} = :sys.get_state(live.pid)

        assert_receive :upgrade_executed, 1_000
        assert socket.assigns.applying_upgrade == true
        assert socket.assigns.upgrade_state == :running
      end
    end
  end

  describe "hot upgrade progress events" do
    test "handles hot_upgrade_progress message", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end,
        deployex_execute: fn _path, _opts ->
          send(test_pid, :upgrade_executed)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-3.0.0.tar.gz"
        download_file(live, filename)

        live
        |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade")
        |> render_click()

        live
        |> element("#danger-button-hotupgrade-execute", "Yes, Apply Hot Upgrade")
        |> render_click()

        msg1 = "Step 1: Validating release"
        msg2 = "Step 2: Backing up current version"
        msg3 = "Step 3: Applying upgrade"
        send(live.pid, {:hot_upgrade_progress, Node.self(), "deployex", msg1})
        send(live.pid, {:hot_upgrade_progress, Node.self(), "deployex", msg2})
        send(live.pid, {:hot_upgrade_progress, Node.self(), "deployex", msg3})

        html = render(live)

        assert_receive :upgrade_executed, 1_000
        assert html =~ msg1
        assert html =~ msg2
        assert html =~ msg3
      end
    end

    test "handles hot_upgrade_complete with success", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end,
        deployex_execute: fn _path, _opts ->
          send(test_pid, :upgrade_executed)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-3.0.0.tar.gz"
        download_file(live, filename)

        live
        |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade")
        |> render_click()

        live
        |> element("#danger-button-hotupgrade-execute", "Yes, Apply Hot Upgrade")
        |> render_click()

        success_msg = "Upgrade completed successfully"
        send(live.pid, {:hot_upgrade_complete, Node.self(), "deployex", :ok, success_msg})

        html = render(live)
        %{socket: socket} = :sys.get_state(live.pid)

        assert_receive :upgrade_executed, 1_000
        assert socket.assigns.upgrade_state == :success
        assert html =~ "Hot upgrade completed successfully!"
      end
    end

    test "handles hot_upgrade_complete with error", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end,
        deployex_execute: fn _path, _opts ->
          send(test_pid, :upgrade_executed)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-3.0.0.tar.gz"
        download_file(live, filename)

        live
        |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade")
        |> render_click()

        live
        |> element("#danger-button-hotupgrade-execute", "Yes, Apply Hot Upgrade")
        |> render_click()

        error_msg = "Upgrade failed: version mismatch"
        send(live.pid, {:hot_upgrade_complete, Node.self(), "deployex", :error, error_msg})

        html = render(live)
        %{socket: socket} = :sys.get_state(live.pid)

        assert_receive :upgrade_executed, 1_000
        assert socket.assigns.upgrade_state == :error
        assert html =~ "Hot upgrade failed!"
      end
    end

    test "ignores hot upgrade events from other nodes", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end,
        deployex_execute: fn _path, _opts ->
          send(test_pid, :upgrade_executed)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-3.0.0.tar.gz"
        download_file(live, filename)

        live
        |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade")
        |> render_click()

        live
        |> element("#danger-button-hotupgrade-execute", "Yes, Apply Hot Upgrade")
        |> render_click()

        send(
          live.pid,
          {:hot_upgrade_progress, :other_node@localhost, "test_app", "Should be ignored"}
        )

        %{socket: socket} = :sys.get_state(live.pid)

        assert_receive :upgrade_executed, 1_000

        assert socket.assigns.upgrade_progress == []
      end
    end

    test "ignores hot upgrade events when not applying upgrade", %{conn: conn} do
      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      send(live.pid, {:hot_upgrade_progress, Node.self(), "test_app", "Should be ignored"})

      %{socket: socket} = :sys.get_state(live.pid)

      assert socket.assigns.upgrade_progress == []
    end
  end

  describe "progress modal" do
    test "shows progress modal during upgrade", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end,
        deployex_execute: fn _path, _opts ->
          send(test_pid, :upgrade_executed)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-3.0.0.tar.gz"
        download_file(live, filename)

        live
        |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade")
        |> render_click()

        html =
          live
          |> element("#danger-button-hotupgrade-execute", "Yes, Apply Hot Upgrade")
          |> render_click()

        assert html =~ "Hot Upgrade Progress"
        assert html =~ "Upgrade Progress"
        assert html =~ "Applying hot upgrade…"
      end
    end

    test "hotupgrade-progress-done event resets state", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn -> :ok end)

      check_data = create_check_data()

      with_mock Deployer.HotUpgrade, [:passthrough],
        deployex_check: fn _path -> {:ok, check_data} end,
        deployex_execute: fn _path, _opts ->
          send(test_pid, :upgrade_executed)
          :ok
        end do
        {:ok, live, _html} = live(conn, ~p"/hotupgrade")

        filename = "deployex-3.0.0.tar.gz"
        download_file(live, filename)

        live
        |> element("#hotupgrade-apply-deployex", "Apply Hot Upgrade")
        |> render_click()

        live
        |> element("#danger-button-hotupgrade-execute", "Yes, Apply Hot Upgrade")
        |> render_click()

        success_msg = "Upgrade completed successfully"
        send(live.pid, {:hot_upgrade_complete, Node.self(), "deployex", :ok, success_msg})

        live
        |> element("#done-button-hotupgrade-progress-done", "Done")
        |> render_click()

        %{socket: socket} = :sys.get_state(live.pid)

        assert_receive :upgrade_executed, 1_000

        assert socket.assigns.downloaded_release == nil
        assert socket.assigns.applying_upgrade == false
        assert socket.assigns.upgrade_state == :init
        assert socket.assigns.upgrade_progress == []
      end
    end
  end

  describe "system info updates" do
    test "handles update_system_info message", %{conn: conn} do
      test_pid = self()

      Deployer.HotUpgradeMock
      |> expect(:subscribe_events, fn ->
        send(test_pid, {:liveview_pid, self()})
        :ok
      end)

      {:ok, live, _html} = live(conn, ~p"/hotupgrade")

      assert_receive {:liveview_pid, liveview_pid}, 1_000

      host_info = %Host.Info{
        host: "Linux",
        description: "Ubuntu 22.04",
        memory_free: 8_000_000_000,
        memory_total: 16_000_000_000,
        cpu: 45.2,
        cpus: 8
      }

      send(liveview_pid, {:update_system_info, host_info})

      html = render(live)

      assert html =~ "Linux"
      assert html =~ "Ubuntu 22.04"
    end
  end

  test "Try to access /hotupgrade/apply without valid release", %{conn: conn} do
    {:error, {:live_redirect, %{to: "/hotupgrade", flash: %{}}}} =
      live(conn, ~p"/hotupgrade/apply")
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

  defp download_file(liveview, filename) do
    content = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73>>

    avatar =
      file_input(liveview, "#upload-form", :hotupgrade, [
        %{
          last_modified: 1_594_171_879_000,
          name: filename,
          content: content,
          size: byte_size(content)
        }
      ])

    render_upload(avatar, filename) =~ "100%"
  end
end
