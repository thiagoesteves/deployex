defmodule Deployer.Engine.Deployment do
  @moduledoc """
  Structure to handle the deployment structure
  """
  @type t :: %__MODULE__{
          state: :init | :active,
          timer_ref: reference() | nil,
          sname: String.t() | nil,
          port: non_neg_integer()
        }

  @derive Jason.Encoder

  defstruct state: :init,
            timer_ref: nil,
            sname: nil,
            port: 0
end
