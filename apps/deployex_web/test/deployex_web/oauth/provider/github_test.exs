defmodule DeployexWeb.OAuth.Provider.GitHubTest do
  use ExUnit.Case, async: true

  alias DeployexWeb.OAuth.Provider.GitHub

  test "extracts a verified email" do
    auth = %{
      info: %{email: "me@co.com"},
      extra: %{raw_info: %{user: %{"email_verified" => true}}}
    }

    assert GitHub.identity(auth) == {:ok, %{email: "me@co.com", verified?: true}}
  end

  test "reports an unverified email as not verified" do
    auth = %{
      info: %{email: "me@co.com"},
      extra: %{raw_info: %{user: %{"email_verified" => false}}}
    }

    assert GitHub.identity(auth) == {:ok, %{email: "me@co.com", verified?: false}}
  end

  test "missing email is an error" do
    auth = %{info: %{email: nil}, extra: %{raw_info: %{user: %{}}}}
    assert {:error, :no_email} = GitHub.identity(auth)
  end
end
