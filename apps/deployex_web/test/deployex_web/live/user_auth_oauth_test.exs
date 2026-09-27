defmodule DeployexWeb.UserAuthOAuthTest do
  # async: false, the tests change the shared OAuth application environment
  use DeployexWeb.ConnCase, async: false

  alias DeployexWeb.UserAuth
  alias Phoenix.LiveView

  @sixty_days 60 * 60 * 24 * 60

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
      allowlist: allowlist
    )
  end

  defp oauth_session(conn, logged_in_at \\ System.os_time(:second)) do
    conn
    |> put_session(:oauth_email, "me@co.com")
    |> put_session(:oauth_logged_in_at, logged_in_at)
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

  test "log_in_oauth_user stores the email and the login time", %{conn: conn} do
    conn = UserAuth.log_in_oauth_user(conn, "me@co.com")

    assert get_session(conn, :oauth_email) == "me@co.com"
    assert is_integer(get_session(conn, :oauth_logged_in_at))
    assert redirected_to(conn) == ~p"/applications"
  end

  test "an allowed OAuth session authenticates", %{conn: conn} do
    conn = conn |> oauth_session() |> UserAuth.fetch_current_user([])
    assert conn.assigns.current_user == %{email: "me@co.com"}

    assert mount_user(oauth_session(conn)) == %{email: "me@co.com"}
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

  test "an OAuth login older than a password session expires", %{conn: conn} do
    conn = oauth_session(conn, System.os_time(:second) - @sixty_days)

    refute UserAuth.fetch_current_user(conn, []).assigns.current_user
    refute mount_user(conn)
  end

  test "an OAuth session without a login time is not accepted", %{conn: conn} do
    conn = put_session(conn, :oauth_email, "me@co.com")

    refute UserAuth.fetch_current_user(conn, []).assigns.current_user
  end
end
