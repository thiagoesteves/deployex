defmodule Deployer.Monitor.Service do
  @moduledoc """
  Structure to handle the monitor service structure
  """
  @type t :: %__MODULE__{
          name: String.t() | nil,
          sname: String.t() | nil,
          language: String.t() | nil,
          port: non_neg_integer(),
          env: list(),
          timeout_app_ready: non_neg_integer(),
          retry_delay_pre_commands: non_neg_integer()
        }

  @derive Jason.Encoder

  defstruct name: nil,
            sname: nil,
            language: nil,
            port: 0,
            env: [],
            timeout_app_ready: :timer.seconds(30),
            retry_delay_pre_commands: :timer.seconds(1)
end
