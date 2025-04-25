defmodule Foundation.Accounts.User do
  @moduledoc """
  This module was copied/modified from the original generate by:
    mix phx.gen.auth Accounts User users

  The module is responsible to handle user structures
  """
  @type t :: %__MODULE__{
          username: String.t() | nil,
          hashed_password: String.t() | nil
        }

  @derive Jason.Encoder

  defstruct username: nil,
            hashed_password: nil

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """

  def valid_password?(%Foundation.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end
end
