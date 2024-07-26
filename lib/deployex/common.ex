defmodule Deployex.Common do
  @moduledoc """
  This module contains functions to be shared among other modules
  """

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Return the short ref
  """
  @spec short_ref(reference()) :: String.t()
  def short_ref(reference) do
    String.slice(inspect(reference), -6..-2)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
