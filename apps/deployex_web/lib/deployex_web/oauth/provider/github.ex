defmodule DeployexWeb.OAuth.Provider.GitHub do
  @moduledoc """
  GitHub provider backed by `assent`.

  Owns the OAuth flow: `authorize_url/0` and `callback/2`. With the
  `user:email` scope, GitHub returns the verified primary email, so a present
  email is verified by construction; the allowlist is the authoritative gate.
  """

  @behaviour DeployexWeb.OAuth.Provider

  alias Assent.Strategy.Github, as: AssentGitHub
  alias DeployexWeb.OAuth.Config

  @impl true
  def authorize_url do
    AssentGitHub.authorize_url(assent_config())
  end

  @impl true
  def callback(params, session_params) do
    config = Keyword.put(assent_config(), :session_params, session_params)

    case AssentGitHub.callback(config, params) do
      {:ok, %{user: %{"email" => email}}} when is_binary(email) ->
        {:ok, %{email: email, verified?: true}}

      {:ok, _other} ->
        {:error, :no_email}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp assent_config do
    [
      client_id: Config.client_id(),
      client_secret: Config.client_secret(),
      redirect_uri: Config.redirect_uri(),
      authorization_params: [scope: "user:email"]
    ]
  end
end
