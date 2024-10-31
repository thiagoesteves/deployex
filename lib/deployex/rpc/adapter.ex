defmodule Deployex.Rpc.Adapter do
  @moduledoc """
  Behaviour that defines Rpc handler
  """

  @callback call(
              node :: atom,
              module :: module,
              function :: atom,
              args :: list,
              timeout :: 0..4_294_967_295 | :infinity
            ) :: any() | {:badrpc, any()}
end
