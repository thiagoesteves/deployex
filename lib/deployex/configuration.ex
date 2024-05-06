defmodule Deployex.Configuration do
  @moduledoc """
  This module contains all paths for services and also initialize the directories
  """

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Ensure all directories are created
  """
  @spec init() :: :ok
  def init do
    [new_path(), current_path(), old_path()]
    |> Enum.each(&File.mkdir_p!/1)
  end

  @doc """
  Return the app name that will be monitored
  """
  @spec monitored_app() :: binary()
  def monitored_app, do: Application.fetch_env!(:deployex, :monitored_app_name)

  @doc """
  Return the app name that will be monitored
  """
  @spec log_path() :: binary()
  def log_path, do: Application.fetch_env!(:deployex, :monitored_app_log_path)

  @doc """
  Base path for the state and service data
  """
  @spec base_path() :: any()
  def base_path, do: Application.fetch_env!(:deployex, :base_path)

  @doc """
  Path for retrieving the new app data
  """
  @spec new_path() :: binary()
  def new_path, do: Path.join(service_path(), "new")

  @doc """
  Path where the app will be running from
  """
  @spec current_path() :: binary()
  def current_path, do: Path.join(service_path(), "current")

  @doc """
  Path to move the previous app files
  """
  @spec old_path() :: binary()
  def old_path, do: Path.join(service_path(), "old")

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp service_path, do: Path.join([base_path(), "service", monitored_app()])
end
