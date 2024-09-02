defmodule DeployexWeb.UserAuthTest do
  use DeployexWeb.ConnCase, async: true

  import Deployex.AccountsFixtures

  alias Deployex.Accounts
  alias DeployexWeb.UserAuth
  alias Phoenix.LiveView

  @remember_me_cookie "_deployex_web_user_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, DeployexWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: user_fixture(), conn: conn}
  end

  describe "log_in_user/3" do
    test "stores the user token in the session", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user)
      assert token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/applications"
      assert Accounts.get_user_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, user: user} do
      conn = conn |> put_session(:to_be_removed, "value") |> UserAuth.log_in_user(user)
      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, user: user} do
      conn = conn |> put_session(:user_return_to, "/hello") |> UserAuth.log_in_user(user)
      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, user: user} do
      conn = conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == 5_184_000
    end
  end

  describe "fetch_current_user/2" do
    test "authenticates user from session", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn = conn |> put_session(:user_token, user_token) |> UserAuth.fetch_current_user([])
      assert conn.assigns.current_user.username == user.username
    end

    test "authenticates user from cookies", %{conn: conn, user: user} do
      logged_in_conn =
        conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.username == user.username
      assert get_session(conn, :user_token) == user_token

      assert get_session(conn, :live_socket_id) ==
               "users_sessions:#{Base.url_encode64(user_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, user: user} do
      _ = Accounts.generate_user_session_token(user)
      conn = UserAuth.fetch_current_user(conn, [])
      refute get_session(conn, :user_token)
      refute conn.assigns.current_user
    end
  end

  describe "on_mount: mount_current_user" do
    test "assigns current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.username == user.username
    end

    test "assigns nil to current_user assign if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end

    test "assigns nil to current_user assign if there isn't a user_token", %{conn: conn} do
      session = conn |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "on_mount: ensure_authenticated" do
    test "authenticates current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:ensure_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.username == user.username
    end

    test "redirects to login page if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: DeployexWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end

    test "redirects to login page if there isn't a user_token", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: DeployexWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "on_mount: :redirect_if_user_is_authenticated" do
    test "redirects if there is an authenticated  user ", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      assert {:halt, _updated_socket} =
               UserAuth.on_mount(
                 :redirect_if_user_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end

    test "doesn't redirect if there is no authenticated user", %{conn: conn} do
      session = conn |> get_session()

      assert {:cont, _updated_socket} =
               UserAuth.on_mount(
                 :redirect_if_user_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end
  end

  describe "redirect_if_user_is_authenticated/2" do
    test "redirects if user is authenticated", %{conn: conn, user: user} do
      conn = conn |> assign(:current_user, user) |> UserAuth.redirect_if_user_is_authenticated([])
      assert conn.halted
      assert redirected_to(conn) == ~p"/applications"
    end

    test "does not redirect if user is not authenticated", %{conn: conn} do
      conn = UserAuth.redirect_if_user_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects if user is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> UserAuth.require_authenticated_user([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "does not redirect if user is authenticated", %{conn: conn, user: user} do
      conn = conn |> assign(:current_user, user) |> UserAuth.require_authenticated_user([])
      refute conn.halted
      refute conn.status
    end
  end
end
