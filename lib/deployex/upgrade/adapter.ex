defmodule Deployex.Upgrade.Adapter do
  @moduledoc """
  Behaviour that defines the upgrade adapter callback
  """

  @callback connect(integer()) :: {:error, :not_connecting} | {:ok, atom()}

  @callback check(integer(), binary(), binary() | charlist() | nil, binary() | charlist()) ::
              {:ok, :full_deployment | :hot_upgrade} | {:error, any()}

  @callback execute(integer(), binary() | charlist() | nil, binary() | charlist() | nil) ::
              :ok | {:error, any()}
end
