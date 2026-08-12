defmodule Deployer.Engine.Deployment do
  @moduledoc """
  Structure to handle the deployment structure
  """
  @typedoc """
  `deploying?` says the worker put a version into service and is waiting for the
  application to report it running, which is what completes a deployment. It is set
  together with the rollback timer and cleared by the report that closes it.
  """
  @type t :: %__MODULE__{
          state: :init | :active,
          timer_ref: reference() | nil,
          sname: String.t() | nil,
          ports: list(),
          deploying?: boolean()
        }

  @derive Jason.Encoder

  defstruct state: :init,
            timer_ref: nil,
            sname: nil,
            ports: [],
            deploying?: false
end
