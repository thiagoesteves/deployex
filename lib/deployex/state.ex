defmodule Deployex.State do
  @moduledoc """
  Module that host the current state and also provide functions to handle it
  """

  alias Deployex.Configuration

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @spec current_version() :: map() | nil
  def current_version do
    case File.read(version_file()) do
      {:ok, data} ->
        version_map(data)["version"]

      _ ->
        nil
    end
  end

  @spec set_current_version_map(Deployex.Storage.version_map()) :: :ok
  def set_current_version_map(version) when is_map(version) do
    File.write!(version_file(), version |> Jason.encode!())
  end

  @spec clear_new() :: :ok
  def clear_new do
    File.rm_rf(Configuration.new_path())
    File.mkdir_p(Configuration.new_path())
    :ok
  end

  @spec update() :: :ok
  def update do
    File.rm_rf(Configuration.old_path())
    File.rename(Configuration.current_path(), Configuration.old_path())
    File.rename(Configuration.new_path(), Configuration.current_path())
    :ok
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp version_file, do: "#{Configuration.base_path()}/current.json"

  defp version_map(data) do
    case Jason.decode(data) do
      {:ok, map} -> map
      _ -> nil
    end
  end
end
