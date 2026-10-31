defmodule DeployexWeb.Helper do
  @moduledoc """
  This module contains functions to be shared among other modules
  """

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  This function exchange "_" and "@" to -

  ## Examples

    iex> alias DeployexWeb.Helper
    ...> assert Helper.normalize_id(:"my_app-1@host") == "my-app-1-host"
    ...> assert Helper.normalize_id("my_app-2@host") == "my-app-2-host"
  """
  @spec normalize_id(node :: atom() | String.t()) :: String.t()
  def normalize_id(node) when is_atom(node) do
    node |> Atom.to_string() |> normalize_id()
  end

  def normalize_id(text) do
    String.replace(text, ["@", "_"], "-")
  end

  @doc """
  Format bytes to human readable string

  ## Examples

    iex> alias DeployexWeb.Helper
    ...> assert Helper.format_bytes(1000) == "1000 B"
    ...> assert Helper.format_bytes(1_048_575) == "1024.0 KB"
    ...> assert Helper.format_bytes(1_073_741_823) == "1024.0 MB"
    ...> assert Helper.format_bytes(1_073_741_824) == "1.0 GB"
  """
  @spec format_bytes(bytes :: non_neg_integer()) :: String.t()
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 2)} KB"

  def format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 2)} MB"

  def format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  @doc """
  Format error to human readable string

  ## Examples

    iex> alias DeployexWeb.Helper
    ...> assert Helper.error_to_string(:too_large) == "File is too large"
    ...> assert Helper.error_to_string(:not_accepted) == "File type not accepted"
    ...> assert Helper.error_to_string(:too_many_files) == "Too many files"
    ...> assert Helper.error_to_string({:error, :invalid}) == "Upload error: {:error, :invalid}"
  """
  def error_to_string(:too_large), do: "File is too large"
  def error_to_string(:not_accepted), do: "File type not accepted"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(error), do: "Upload error: #{inspect(error)}"
end
