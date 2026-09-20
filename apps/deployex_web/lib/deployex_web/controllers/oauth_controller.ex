defmodule DeployexWeb.OAuthController do
  @moduledoc """
  Handles the OAuth request/callback for 3rd-party SSO.

  `plug Ueberauth` runs the provider flow (request phase redirects to the
  provider; callback phase populates `ueberauth_auth` or `ueberauth_failure`).
  On a verified, allow-listed email we establish a session-only login via
  `UserAuth`; otherwise we redirect back to the login page. No user is stored.
  """
  use DeployexWeb, :controller

  plug Ueberauth

  alias DeployexWeb.OAuth.{Allowlist, Config}
  alias DeployexWeb.UserAuth

  # ueberauth's request phase normally redirects to the provider and halts, so
  # this action is only reached for an unknown/misconfigured provider.
  def request(conn, _params) do
    conn
    |> put_flash(:error, "Unknown authentication provider.")
    |> redirect(to: ~p"/users/log_in")
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Sign-in failed.")
    |> redirect(to: ~p"/users/log_in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    with {:ok, %{email: email, verified?: true}} <- Config.provider_module().identity(auth),
         :ok <- Allowlist.check(email, Config.allowlist()) do
      UserAuth.log_in_oauth_user(conn, email)
    else
      _ ->
        conn
        |> put_flash(:error, "Not authorized for this instance.")
        |> redirect(to: ~p"/users/log_in")
    end
  end
end
