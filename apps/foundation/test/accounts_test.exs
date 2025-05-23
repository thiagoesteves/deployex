defmodule Foundation.AccountsTest do
  use ExUnit.Case, async: true

  alias Foundation.Accounts

  test "get_user_by_username_and_password/2 success" do
    assert %Accounts.User{hashed_password: _, username: "admin"} =
             Accounts.get_user_by_username_and_password("admin", "deployex")
  end

  test "get_user_by_username_and_password/2 invalid user" do
    refute Accounts.get_user_by_username_and_password("test", "deployex")
  end

  test "generate_user_session_token/1" do
    token = Accounts.generate_user_session_token(%Accounts.UserToken{username: "admin"})
    assert is_binary(token)
  end

  test "get_user_by_session_token/1 success" do
    token = Accounts.generate_user_session_token(%{username: "admin"})

    assert %Accounts.User{hashed_password: nil, username: "admin"} ==
             Accounts.get_user_by_session_token(token)
  end

  test "get_user_by_session_token/1 error" do
    refute Accounts.get_user_by_session_token("token")
  end
end
