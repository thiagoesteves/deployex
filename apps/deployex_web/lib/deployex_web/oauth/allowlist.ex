defmodule DeployexWeb.OAuth.Allowlist do
  @moduledoc """
  Decides whether an authenticated email may access DeployEx.

  Deny by default: an empty or missing allowlist denies everyone. Access is
  granted only when the email matches a configured email or domain. Matching
  is case-insensitive.
  """

  @type config :: %{optional(:emails) => [String.t()], optional(:domains) => [String.t()]}

  @spec check(String.t(), config() | nil) :: :ok | :denied
  def check(_email, nil), do: :denied

  def check(email, config) do
    emails = config |> Map.get(:emails, []) |> Enum.map(&String.downcase/1)
    domains = config |> Map.get(:domains, []) |> Enum.map(&String.downcase/1)

    email = String.downcase(email)
    domain = email |> String.split("@") |> List.last()

    cond do
      email in emails -> :ok
      domain in domains -> :ok
      true -> :denied
    end
  end
end
