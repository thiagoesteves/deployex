defmodule Deployer.Upgrade.Adapter do
  @moduledoc """
  Behaviour that defines the upgrade adapter callback
  """

  @callback connect(integer()) :: {:error, :not_connecting} | {:ok, atom()}
  @callback check(
              integer(),
              String.t(),
              String.t(),
              binary(),
              binary() | charlist() | nil,
              binary() | charlist()
            ) ::
              {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  @callback execute(
              integer(),
              String.t(),
              String.t(),
              binary() | charlist() | nil,
              binary() | charlist() | nil
            ) ::
              :ok | {:error, any()}
end
