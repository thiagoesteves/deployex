defmodule Foundation.Accounts.UserToken do
  @moduledoc """
  This module was copied/modified from the original generate by:
    mix phx.gen.auth Accounts User users

  The module is responsible to handle user token structures
  """
  @rand_size 32

  # It is very important to keep the reset password token expiry short,
  # since someone with access to the email may take over the account.
  @session_validity_in_days 60

  @type t :: %__MODULE__{
          token: String.t() | nil,
          context: String.t() | nil,
          username: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @derive Jason.Encoder

  defstruct token: nil,
            context: nil,
            username: nil,
            inserted_at: nil

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix' default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired. The token system can also be extended
  to store additional data, such as the device used for logging in.
  You could then use this information to display all valid sessions
  and devices in the UI and allow users to explicitly expire any
  session they deem invalid.
  """
  def build_session_token(username) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {token,
     %__MODULE__{
       token: token,
       context: "session",
       username: username,
       inserted_at: DateTime.utc_now()
     }}
  end

  @doc """
  Checks if the token is valid

  The token is valid if it has not expired (after @session_validity_in_days).
  """
  def verify_session_token(%{inserted_at: inserted_at} = user_token) do
    if DateTime.diff(DateTime.utc_now(), inserted_at, :day) < @session_validity_in_days do
      user_token
    else
      nil
    end
  end

  def verify_session_token(_user_token), do: nil
end
