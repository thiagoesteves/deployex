defmodule Deployer.Engine.Deployment do
  @moduledoc """
  Structure to handle the deployment structure
  """
  @type t :: %__MODULE__{
          state: :init | :active,
          timer_ref: reference() | nil,
          sname: String.t() | nil,
          ports: list()
        }

  @derive Jason.Encoder

  defstruct state: :init,
            timer_ref: nil,
            sname: nil,
            ports: []
end
