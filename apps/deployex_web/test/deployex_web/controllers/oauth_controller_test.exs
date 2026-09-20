defmodule DeployexWeb.OAuthControllerTest do
  # async: false — mutates the shared application environment; calls the
  # callback action directly to bypass the real Ueberauth plug.
  use DeployexWeb.ConnCase, async: false

  import Mox

  alias DeployexWeb.OAuth.ProviderMock

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:deployex_web, DeployexWeb.OAuth)

    on_exit(fn ->
      if original do
        Application.put_env(:deployex_web, DeployexWeb.OAuth, original)
      else
        Application.delete_env(:deployex_web, DeployexWeb.OAuth)
      end
    end)

    :ok
  end

  defp put_oauth_config(allowlist) do
    Application.put_env(:deployex_web, DeployexWeb.OAuth,
      provider: ProviderMock,
      allowlist: allowlist
    )
  end

  defp base_conn do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> Phoenix.Controller.fetch_flash([])
  end

  test "allowed verified email logs in: session set, redirect to app" do
    put_oauth_config(%{emails: ["me@co.com"], domains: []})
    expect(ProviderMock, :identity, fn _auth -> {:ok, %{email: "me@co.com", verified?: true}} end)

    conn =
      base_conn()
      |> assign(:ueberauth_auth, %{})
      |> DeployexWeb.OAuthController.callback(%{})

    assert get_session(conn, :oauth_email) == "me@co.com"
    assert redirected_to(conn) == "/applications"
  end

  test "email not on the allowlist is denied: no session, back to login" do
    put_oauth_config(%{emails: [], domains: []})
    expect(ProviderMock, :identity, fn _ -> {:ok, %{email: "stranger@evil.com", verified?: true}} end)

    conn =
      base_conn()
      |> assign(:ueberauth_auth, %{})
      |> DeployexWeb.OAuthController.callback(%{})

    assert get_session(conn, :oauth_email) == nil
    assert redirected_to(conn) == "/users/log_in"
  end

  test "unverified email is denied" do
    put_oauth_config(%{emails: ["me@co.com"], domains: []})
    expect(ProviderMock, :identity, fn _ -> {:ok, %{email: "me@co.com", verified?: false}} end)

    conn =
      base_conn()
      |> assign(:ueberauth_auth, %{})
      |> DeployexWeb.OAuthController.callback(%{})

    assert get_session(conn, :oauth_email) == nil
    assert redirected_to(conn) == "/users/log_in"
  end

  test "ueberauth_failure redirects to login" do
    put_oauth_config(%{emails: [], domains: []})

    conn =
      base_conn()
      |> assign(:ueberauth_failure, %{errors: []})
      |> DeployexWeb.OAuthController.callback(%{})

    assert redirected_to(conn) == "/users/log_in"
  end
end
