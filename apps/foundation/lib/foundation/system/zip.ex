defmodule Foundation.System.Zip do
  @moduledoc false

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec unzip(file :: charlist(), options :: Keyword.t()) :: {:ok, any()} | {:error, any()}
  def unzip(file, options), do: :zip.unzip(file, options)
end
