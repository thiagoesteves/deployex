defmodule Foundation.Accounts do
  @moduledoc """
  This module was copied/modified from the original generate by:
    mix phx.gen.auth Accounts User users

  The Accounts context
  """

  alias Foundation.Accounts.{User, UserToken}
  alias Foundation.Catalog

  @default_user "admin"

  ## Database getters

  @doc """
  Gets a user by username and password.

  ## Examples

      iex> get_user_by_username_and_password("foo", "correct_password")
      %User{}

      iex> get_user_by_username_and_password("foo", "invalid_password")
      nil

  """
  def get_user_by_username_and_password(@default_user, password)
      when is_binary(password) do
    if User.valid_password?(admin_user(), password), do: admin_user()
  end

  def get_user_by_username_and_password(_username, _password), do: nil

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, %UserToken{} = user_token} = UserToken.build_session_token(user.username)
    Catalog.add_user_session_token(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    token
    |> Catalog.get_user_session_token_by_token()
    |> UserToken.verify_session_token()
    |> case do
      nil -> nil
      user_token -> %User{username: user_token.username}
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  # NOTE: In order to generate the hashed password:
  #       > Bcrypt.hash_pwd_salt("deployex")
  defp admin_user do
    %User{
      username: "admin",
      hashed_password: Application.get_env(:foundation, __MODULE__)[:admin_hashed_password]
    }
  end
end
