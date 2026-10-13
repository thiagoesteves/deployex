defmodule DeployexWeb.OAuth.Provider do
  @moduledoc """
  Contract for an OAuth provider seam.

  With a function-based library (assent) the provider owns the whole flow:
  build the authorize URL, then exchange the callback for a normalized
  identity. This keeps the controller lib-agnostic and the library swappable.
  """

  @type identity :: %{email: String.t(), verified?: boolean()}

  @callback authorize_url() ::
              {:ok, %{url: String.t(), session_params: map()}} | {:error, term()}

  @callback callback(params :: map(), session_params :: map()) ::
              {:ok, identity()} | {:error, term()}
end
