defmodule Deployer.Resources do
  @moduledoc """
  CPU, memory and the process, port and atom limits of each running instance, for every language.

  `Deployer.Resources.Server` samples them every few seconds, with no change in the monitored app: CPU from
  the runtime counter of the instance's BEAM over RPC, memory from its OS process, and the counts and limits
  over RPC. Each count keeps a minute series of the last hour for its trend.
  """

  alias Deployer.Resources.Server

  defmodule Limit do
    @moduledoc """
    A count with its limit, and how much the count changed over the last `change_minutes`.
    """
    @type t :: %__MODULE__{
            count: non_neg_integer(),
            limit: pos_integer(),
            percent: non_neg_integer(),
            change_percent: integer() | nil,
            change_minutes: non_neg_integer() | nil
          }

    defstruct [:count, :limit, :percent, :change_percent, :change_minutes]
  end

  @type t :: %__MODULE__{
          sname: String.t(),
          cpu: non_neg_integer() | nil,
          memory: non_neg_integer() | nil,
          process: Limit.t() | nil,
          port: Limit.t() | nil,
          atom: Limit.t() | nil,
          sampled_at: DateTime.t() | nil
        }

  defstruct [:sname, :cpu, :memory, :process, :port, :atom, :sampled_at]

  @doc """
  Returns the last sample of an instance, or nil when it has none.

  `cpu` is a percentage of all the host's cores, `memory` the resident memory in bytes.
  """
  @spec get(sname :: String.t()) :: t() | nil
  def get(sname), do: Server.get(sname)
end
