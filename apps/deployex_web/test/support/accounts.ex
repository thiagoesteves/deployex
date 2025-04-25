defmodule DeployexWeb.AccountsFixtures do
  @moduledoc """
  This module will handle the accounts fixture
  """

  def user_fixture do
    %Foundation.Accounts.User{
      username: "admin",
      hashed_password: "$2b$12$bI298wLHontVoAtpGAWkOOm5UwhFR4P8dh7IciMaaNTtwq4xtgcTS"
    }
  end
end
