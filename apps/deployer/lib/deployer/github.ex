defmodule Deployer.Github do
  @moduledoc """
  This module contains deployex information about the latest release
  """

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  @spec latest_release() :: {:ok, __MODULE__.Release.t()}
  def latest_release, do: __MODULE__.Release.latest_release()

  @spec download_artifact(url :: String.t(), token :: String.t()) :: :ok
  def download_artifact(url, token), do: __MODULE__.Artifacts.download_artifact(url, token)

  @spec subscribe_download_events() :: :ok
  def subscribe_download_events, do: __MODULE__.Artifacts.subscribe_download_events()

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
