defmodule Deployex.Release.Adapter do
  @moduledoc """
  Behaviour that defines the release adapter callback
  """

  @callback get_current_version_map() :: Deployex.Release.version_map() | nil
  @callback download_and_unpack(integer(), String.t()) ::
              {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
end
