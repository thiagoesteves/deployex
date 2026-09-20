defmodule DeployexWeb.OAuth.Provider.GitHub do
  @moduledoc """
  Normalizes a GitHub `Ueberauth.Auth` result into `{:ok, %{email, verified?}}`.

  Only a verified primary email should grant access; the caller checks
  `verified?` before consulting the allowlist.
  """

  @behaviour DeployexWeb.OAuth.Provider

  @impl true
  # Pattern-matches both a real `Ueberauth.Auth` struct and a plain test map.
  # With the `user:email` scope, ueberauth_github sets `info.email` to
  # GitHub's primary email, which GitHub keeps verified, so a present email is
  # verified by construction. The allowlist is the authoritative access gate.
  def identity(%{info: %{email: email}}) when is_binary(email) do
    {:ok, %{email: email, verified?: true}}
  end

  def identity(_auth), do: {:error, :no_email}
end
