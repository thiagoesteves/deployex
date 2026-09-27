defmodule DeployexWeb.OAuthController do
  @moduledoc """
  Handles the OAuth request/callback for 3rd-party SSO (assent-backed).

  The provider seam owns the flow, so this controller is lib-agnostic: the
  request builds the authorize URL and stores the CSRF `session_params`. The
  callback exchanges the code for a verified, allow-listed email and
  establishes a session-only login. No user is stored.
  """
  use DeployexWeb, :controller

  require Logger

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
    session_params = get_session(conn, :oauth_session_params)
    conn = delete_session(conn, :oauth_session_params)

    case authenticate(params, session_params) do
      {:ok, email} ->
        UserAuth.log_in_oauth_user(conn, email)

      {:error, reason} ->
        Logger.warning("OAuth sign-in denied: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Not authorized for this instance.")
        |> redirect(to: ~p"/users/log_in")
    end
  end

  # No session params: the callback reached a session that did not start the sign-in, for
  # example DeployEx opened on another host than the redirect_uri host
  defp authenticate(_params, nil), do: {:error, :no_sign_in_in_progress}

  defp authenticate(params, session_params) do
    case Config.provider_module().callback(params, session_params) do
      {:ok, %{email: email, verified?: true}} ->
        if Allowlist.check(email, Config.allowlist()) == :ok,
          do: {:ok, email},
          else: {:error, {:not_in_allowlist, email}}

      {:ok, %{email: email}} ->
        {:error, {:unverified_email, email}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
