defmodule Deployex.AccountsFixtures do
  @moduledoc """
  This module will handle the accounts fixture
  """

  def user_fixture do
    %Deployex.Accounts.User{
      username: "admin",
      hashed_password: "$2b$12$smSkCQaC/9ikq4UeZECBuu7M23BiW9bvTyRQ2p25PAYTZjNQ42ASi"
    }
  end
end
