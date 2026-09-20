defmodule DeployexWeb.UserAuthTest do
  use DeployexWeb.ConnCase, async: true

  alias DeployexWeb.UserAuth

  describe "log_out_user/1" do
    test "clears an OAuth session and redirects to login", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{oauth_email: "me@co.com"})
        |> UserAuth.log_out_user()

      refute get_session(conn, :oauth_email)
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "clears a password session and redirects to login", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{user_token: "some-token"})
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "fetch_current_user/2" do
    test "sets current_user from an OAuth session with no DB lookup", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{oauth_email: "me@co.com"})
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user == %{email: "me@co.com"}
    end

    test "no session yields no current_user", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.fetch_current_user([])

      refute conn.assigns.current_user
    end
  end
end
