defmodule Deployer.Release.Adapter do
  @moduledoc """
  Behaviour that defines the release adapter callback
  """

  @callback download_version_map(String.t()) :: map()
  @callback download_release(String.t(), String.t(), String.t()) :: :ok
end
