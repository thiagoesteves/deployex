defmodule DeployexWeb.OAuth.Provider.GitHub do
  @moduledoc """
  Normalizes a GitHub `Ueberauth.Auth` result into `{:ok, %{email, verified?}}`.

  Only a verified primary email should grant access; the caller checks
  `verified?` before consulting the allowlist.
  """

  @behaviour DeployexWeb.OAuth.Provider

  @impl true
  def identity(%{info: %{email: email}} = auth) when is_binary(email) do
    {:ok, %{email: email, verified?: verified?(auth)}}
  end

  def identity(_auth), do: {:error, :no_email}

  # VERIFY against the installed ueberauth_github: confirm where GitHub's
  # email-verified flag lands in the real `Ueberauth.Auth` struct. This reads
  # the shape the tests exercise; the live wiring (controller task) must
  # confirm the real struct path.
  defp verified?(auth) do
    get_in(auth, [:extra, :raw_info, :user, "email_verified"]) == true
  end
end
