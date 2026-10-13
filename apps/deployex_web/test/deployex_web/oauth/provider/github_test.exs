defmodule DeployexWeb.OAuth.Provider.GitHubTest do
  # async: false, the tests change the shared application environment
  use ExUnit.Case, async: false

  alias DeployexWeb.OAuth.Provider.GitHub

  # Stands in for GitHub's token, user and emails endpoints
  defmodule FakeGitHub do
    @moduledoc false
    @behaviour Assent.HTTPAdapter

    alias Assent.HTTPAdapter.HTTPResponse

    @impl true
    def request(
          :post,
          "https://github.com/login/oauth/access_token" <> _,
          _body,
          _headers,
          _opts
        ),
        do:
          {:ok,
           %HTTPResponse{status: 200, body: %{"access_token" => "t", "token_type" => "bearer"}}}

    def request(:get, "https://api.github.com/user/emails" <> _, _body, _headers, _opts),
      do:
        {:ok,
         %HTTPResponse{status: 200, body: Application.get_env(:deployex_web, :fake_github_emails)}}

    def request(:get, "https://api.github.com/user" <> _, _body, _headers, _opts),
      do: {:ok, %HTTPResponse{status: 200, body: %{"id" => 1, "login" => "me"}}}
  end

  setup do
    oauth = Application.get_env(:deployex_web, DeployexWeb.OAuth)
    adapter = Application.get_env(:assent, :http_adapter)

    on_exit(fn ->
      restore(:deployex_web, DeployexWeb.OAuth, oauth)
      restore(:assent, :http_adapter, adapter)
      Application.delete_env(:deployex_web, :fake_github_emails)
    end)

    Application.put_env(:assent, :http_adapter, FakeGitHub)

    Application.put_env(:deployex_web, DeployexWeb.OAuth,
      client_id: "Ov23liExample",
      client_secret: "secret",
      redirect_uri: "http://localhost:5001/auth/github/callback"
    )

    :ok
  end

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)

  defp callback_with_emails(emails) do
    Application.put_env(:deployex_web, :fake_github_emails, emails)
    GitHub.callback(%{"code" => "c", "state" => "s"}, %{state: "s"})
  end

  test "a verified primary email is returned as verified" do
    assert callback_with_emails([
             %{"email" => "me@co.com", "primary" => true, "verified" => true}
           ]) ==
             {:ok, %{email: "me@co.com", verified?: true}}
  end

  test "an unverified primary email is returned as not verified" do
    assert callback_with_emails([
             %{"email" => "me@co.com", "primary" => true, "verified" => false}
           ]) ==
             {:ok, %{email: "me@co.com", verified?: false}}
  end

  test "an account with no primary email returns no_email" do
    assert callback_with_emails([
             %{"email" => "me@co.com", "primary" => false, "verified" => true}
           ]) ==
             {:error, :no_email}
  end
end
