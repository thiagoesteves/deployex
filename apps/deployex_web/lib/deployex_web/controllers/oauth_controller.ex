defmodule DeployexWeb.OAuthController do
  @moduledoc """
  Handles the OAuth request/callback for 3rd-party SSO (assent-backed).

  The provider seam owns the flow, so this controller is lib-agnostic: the
  request builds the authorize URL and stores the CSRF `session_params`; the
  callback exchanges the code for a verified, allow-listed email and
  establishes a session-only login. No user is stored.
  """
  use DeployexWeb, :controller

  alias DeployexWeb.OAuth.{Allowlist, Config}
  alias DeployexWeb.UserAuth

  def request(conn, _params) do
    case Config.provider_module().authorize_url() do
      {:ok, %{url: url, session_params: session_params}} ->
        conn
        |> put_session(:oauth_session_params, session_params)
        |> redirect(external: url)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Sign-in failed.")
        |> redirect(to: ~p"/users/log_in")
    end
  end

  def callback(conn, params) do
    session_params = get_session(conn, :oauth_session_params) || %{}

    with {:ok, %{email: email, verified?: true}} <-
           Config.provider_module().callback(params, session_params),
         :ok <- Allowlist.check(email, Config.allowlist()) do
      conn
      |> delete_session(:oauth_session_params)
      |> UserAuth.log_in_oauth_user(email)
    else
      _ ->
        conn
        |> delete_session(:oauth_session_params)
        |> put_flash(:error, "Not authorized for this instance.")
        |> redirect(to: ~p"/users/log_in")
    end
  end
end
