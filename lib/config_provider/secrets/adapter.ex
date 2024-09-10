defmodule Deployex.ConfigProvider.Secrets.Adapter do
  @moduledoc """
  Behaviour that defines the secret retrieval
  """

  @callback secrets([Keyword.t()], String.t(), [Keyword.t()]) :: map()
end
