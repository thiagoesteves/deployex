defmodule DeployexWeb.UserAuthOAuthTest do
  # async: false, the tests change the shared OAuth application environment
  use DeployexWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias DeployexWeb.UserAuth
  alias Foundation.Accounts
  alias Foundation.Accounts.UserToken
  alias Foundation.Catalog
  alias Phoenix.LiveView

  @sixty_days 60 * 60 * 24 * 60
  @remember_me_cookie "_deployex_web_user_remember_me"

  setup %{conn: conn} do
    original = Application.get_env(:deployex_web, DeployexWeb.OAuth)

    on_exit(fn ->
      if original do
        Application.put_env(:deployex_web, DeployexWeb.OAuth, original)
      else
        Application.delete_env(:deployex_web, DeployexWeb.OAuth)
      end
    end)

    put_oauth_config(%{emails: ["me@co.com"], domains: []})

    conn =
      conn
      |> Map.replace!(:secret_key_base, DeployexWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{conn: conn}
  end

  defp put_oauth_config(allowlist) do
    Application.put_env(:deployex_web, DeployexWeb.OAuth,
      client_id: "Ov23liExample",
      client_secret: "secret",
      redirect_uri: "http://localhost:5001/auth/github/callback",
      allowlist: allowlist
    )
  end

  defp oauth_session(conn) do
    token = Accounts.generate_user_session_token(%{username: "me@co.com"})
    put_session(conn, :oauth_token, token)
  end

  defp mount_user(conn) do
    session = get_session(conn)

    socket = %LiveView.Socket{
      endpoint: DeployexWeb.Endpoint,
      assigns: %{__changed__: %{}, flash: %{}}
    }

    {:cont, socket} = UserAuth.on_mount(:mount_current_user, %{}, session, socket)
    socket.assigns.current_user
  end

  test "log_in_oauth_user stores a session token for the email", %{conn: conn} do
    conn = UserAuth.log_in_oauth_user(conn, "me@co.com")

    assert token = get_session(conn, :oauth_token)
    assert %{username: "me@co.com"} = Accounts.get_user_by_session_token(token)
    assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
    assert redirected_to(conn) == ~p"/applications"
  end

  test "log_in_oauth_user drops a remember-me cookie from a password login", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie(@remember_me_cookie, "stale")
      |> UserAuth.log_in_oauth_user("me@co.com")

    assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
  end

  test "an allowed OAuth session authenticates", %{conn: conn} do
    conn = oauth_session(conn)

    assert UserAuth.fetch_current_user(conn, []).assigns.current_user == %{email: "me@co.com"}
    assert mount_user(conn) == %{email: "me@co.com"}
  end

  test "an email removed from the allowlist loses access", %{conn: conn} do
    conn = oauth_session(conn)
    put_oauth_config(%{emails: ["someone@co.com"], domains: []})

    refute UserAuth.fetch_current_user(conn, []).assigns.current_user
    refute mount_user(conn)
  end

  test "an OAuth session is not accepted when OAuth is turned off", %{conn: conn} do
    conn = oauth_session(conn)
    Application.put_env(:deployex_web, DeployexWeb.OAuth, [])

    refute UserAuth.fetch_current_user(conn, []).assigns.current_user
    refute mount_user(conn)
  end

  test "an OAuth session older than a password session expires", %{conn: conn} do
    token = :crypto.strong_rand_bytes(32)

    :ok =
      Catalog.add_user_session_token(%UserToken{
        token: token,
        context: "session",
        username: "me@co.com",
        inserted_at: DateTime.add(DateTime.utc_now(), -@sixty_days, :second)
      })

    conn = put_session(conn, :oauth_token, token)

    refute UserAuth.fetch_current_user(conn, []).assigns.current_user
    refute mount_user(conn)
  end

  test "an OAuth session with an unknown token is not accepted", %{conn: conn} do
    conn = put_session(conn, :oauth_token, "unknown")

    refute UserAuth.fetch_current_user(conn, []).assigns.current_user
    refute mount_user(conn)
  end

  test "a session copied before logout no longer authenticates", %{conn: conn} do
    copied = conn |> UserAuth.log_in_oauth_user("me@co.com") |> get_session()

    conn |> init_test_session(copied) |> UserAuth.log_out_user()
    conn = init_test_session(conn, copied)

    refute UserAuth.fetch_current_user(conn, []).assigns.current_user
    refute mount_user(conn)
  end

  describe "an open LiveView when the auth config changes" do
    setup [:set_mox_global, :verify_on_exit!]

    setup do
      Deployer.StatusMock
      |> stub(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
      |> stub(:subscribe, fn -> :ok end)
      |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

      :ok
    end

    @tag :capture_log
    test "stays open when the email is still allowed", %{conn: conn} do
      {:ok, liveview, _html} = conn |> oauth_session() |> live(~p"/applications")

      put_oauth_config(%{emails: ["me@co.com", "someone@co.com"], domains: []})
      send(liveview.pid, {:watcher_auth_apply, Node.self()})

      assert render(liveview) =~ "Applications"
    end

    @tag :capture_log
    test "redirects to the login page when the email is removed", %{conn: conn} do
      {:ok, liveview, _html} = conn |> oauth_session() |> live(~p"/applications")

      put_oauth_config(%{emails: ["someone@co.com"], domains: []})
      send(liveview.pid, {:watcher_auth_apply, Node.self()})

      flash = assert_redirect(liveview, ~p"/users/log_in")
      assert flash["error"] == "Not authorized for this instance."
    end

    @tag :capture_log
    test "redirects to the login page when OAuth is turned off", %{conn: conn} do
      {:ok, liveview, _html} = conn |> oauth_session() |> live(~p"/applications")

      Application.put_env(:deployex_web, DeployexWeb.OAuth, client_secret: "secret")
      send(liveview.pid, {:watcher_auth_apply, Node.self()})

      assert_redirect(liveview, ~p"/users/log_in")
    end

    @tag :capture_log
    test "is told when an auth change is applied", %{conn: conn} do
      {:ok, liveview, _html} = conn |> oauth_session() |> live(~p"/applications")

      put_oauth_config(%{emails: [], domains: []})

      Phoenix.PubSub.broadcast(
        Foundation.PubSub,
        "deployex::config::auth::apply",
        {:watcher_auth_apply, Node.self()}
      )

      assert_redirect(liveview, ~p"/users/log_in")
    end

    @tag :capture_log
    test "the hook is a remote capture, so it survives a hot upgrade of UserAuth", %{conn: conn} do
      {:ok, liveview, _html} = conn |> oauth_session() |> live(~p"/applications")

      %{socket: socket} = :sys.get_state(liveview.pid)

      %{function: hook} =
        Enum.find(socket.private.lifecycle.handle_info, &(&1.id == :oauth_access))

      assert Function.info(hook, :type) == {:type, :external}
    end

    @tag :capture_log
    test "a password session is not affected", %{conn: conn} do
      {:ok, liveview, _html} =
        conn
        |> log_in_user(%{username: "admin"})
        |> live(~p"/applications")

      Application.put_env(:deployex_web, DeployexWeb.OAuth, [])

      Phoenix.PubSub.broadcast(
        Foundation.PubSub,
        "deployex::config::auth::apply",
        {:watcher_auth_apply, Node.self()}
      )

      assert render(liveview) =~ "Applications"
    end
  end
end
