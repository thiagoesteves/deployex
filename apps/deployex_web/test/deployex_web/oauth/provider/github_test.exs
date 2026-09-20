defmodule DeployexWeb.OAuth.Provider.GitHubTest do
  use ExUnit.Case, async: true

  alias DeployexWeb.OAuth.Provider.GitHub

  test "returns the email from a github auth result" do
    auth = %{info: %{email: "me@co.com"}}
    assert GitHub.identity(auth) == {:ok, %{email: "me@co.com", verified?: true}}
  end

  test "works on a struct-shaped auth (dot access, no Access needed)" do
    # A real Ueberauth.Auth is a struct; pattern matching handles it the same.
    auth = %{info: %{email: "me@co.com"}, extra: %{raw_info: %{}}}
    assert {:ok, %{email: "me@co.com"}} = GitHub.identity(auth)
  end

  test "missing email is an error" do
    assert {:error, :no_email} = GitHub.identity(%{info: %{email: nil}})
    assert {:error, :no_email} = GitHub.identity(%{})
  end
end
