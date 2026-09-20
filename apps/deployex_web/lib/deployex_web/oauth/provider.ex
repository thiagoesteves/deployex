defmodule DeployexWeb.OAuth.Provider do
  @moduledoc """
  Contract for an OAuth provider seam.

  An implementation normalizes a provider-specific auth result into a plain
  identity map, so the rest of the app never depends on the underlying
  library. This keeps the provider (and the library behind it) swappable.
  """

  @type identity :: %{email: String.t(), verified?: boolean()}

  @callback identity(auth :: any()) :: {:ok, identity()} | {:error, term()}
end
