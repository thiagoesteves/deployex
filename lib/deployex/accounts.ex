defmodule Deployex.Accounts do
  @moduledoc """
  This module was copied/modified from the original generate by:
    mix phx.gen.auth Accounts User users

  The Accounts context
  """

  alias Deployex.Accounts.{User, UserToken}
  alias Deployex.Storage

  # NOTE: In order to generate the hashed password:
  #       > Bcrypt.hash_pwd_salt("admin")
  #       "$2b$12$smSkCQaC/9ikq4UeZECBuu7M23BiW9bvTyRQ2p25PAYTZjNQ42ASi"
  @default_admin_user %User{
    username: "admin",
    hashed_password: "$2b$12$smSkCQaC/9ikq4UeZECBuu7M23BiW9bvTyRQ2p25PAYTZjNQ42ASi"
  }

  ## Database getters

  @doc """
  Gets a user by username and password.

  ## Examples

      iex> get_user_by_username_and_password("foo", "correct_password")
      %User{}

      iex> get_user_by_username_and_password("foo", "invalid_password")
      nil

  """
  def get_user_by_username_and_password("admin", password)
      when is_binary(password) do
    if User.valid_password?(@default_admin_user, password), do: @default_admin_user
  end

  def get_user_by_username_and_password(_username, _password), do: nil

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Deployex.Storage.add_user_session_token(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    token
    |> Storage.get_user_session_token_by_token()
    |> UserToken.verify_session_token()
    |> case do
      nil -> nil
      user_token -> %User{username: user_token.username}
    end
  end
end
