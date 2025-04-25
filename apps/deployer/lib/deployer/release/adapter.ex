defmodule Deployer.Release.Adapter do
  @moduledoc """
  Behaviour that defines the release adapter callback
  """

  @callback get_current_version_map() :: Deployer.Release.Version.t()
  @callback download_and_unpack(integer(), String.t()) ::
              {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
end
