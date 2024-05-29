defmodule Deployex.Storage.Adapter do
  @moduledoc """
  Behaviour that defines the Storage adapter callback
  """

  @callback get_current_version_map() :: Deployex.Storage.version_map() | nil
  @callback download_and_unpack(integer(), String.t()) ::
              {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
end
