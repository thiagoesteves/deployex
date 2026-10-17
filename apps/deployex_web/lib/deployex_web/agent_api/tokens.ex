defmodule DeployexWeb.AgentApi.Tokens do
  @moduledoc """
  Checks the bearer tokens of the agent API against `DEPLOYEX_API_TOKENS`.

  The secret is a comma-separated list of `name:scopes:sha256` entries, with the
  scopes joined by `+` and the hex SHA-256 of the token, for example
  `ci:read:9f86d081...,controller:read:2c26b46b...`. DeployEx keeps only the hashes.
  """

  require Logger

  @scopes ["read"]

  @type t :: %{name: String.t(), scopes: [String.t()], hash: binary()}

  @doc """
  Returns the token entry whose hash matches the given token.
  """
  @spec authenticate(token :: String.t() | nil) :: {:ok, t()} | :error
  def authenticate(token) when is_binary(token) and token != "" do
    hash = :crypto.hash(:sha256, token)

    case Enum.find(valid_tokens(), &Plug.Crypto.secure_compare(&1.hash, hash)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  def authenticate(_token), do: :error

  @spec allows?(token :: t(), scope :: String.t()) :: boolean()
  def allows?(%{scopes: scopes}, scope), do: scope in scopes

  @doc """
  Parses the secret into the valid entries and the positions of the invalid ones.

  A value that is not a string, such as a JSON list in a cloud secret, is one invalid entry.
  """
  @spec parse(value :: term()) :: {[t()], [pos_integer()]}
  def parse(nil), do: {[], []}

  def parse(value) when not is_binary(value), do: {[], [1]}

  def parse(value) do
    {valid, invalid} =
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {entry, position}, {valid, invalid} ->
        case parse_entry(entry) do
          {:ok, token} -> {[token | valid], invalid}
          :error -> {valid, [position | invalid]}
        end
      end)

    {Enum.reverse(valid), Enum.reverse(invalid)}
  end

  @doc """
  Logs a warning for each invalid entry, and when the API is on with no valid token.
  """
  @spec warn_if_misconfigured() :: :ok
  def warn_if_misconfigured do
    {valid, invalid} = parse(configured())

    Enum.each(invalid, fn position ->
      Logger.warning(
        "Agent API token entry #{position} in DEPLOYEX_API_TOKENS is ignored, expected name:scopes:sha256"
      )
    end)

    if valid == [] and Phoenix.Endpoint.server?(:deployex_web, DeployexWeb.AgentApi.Endpoint) do
      Logger.warning("Agent API is on with no valid token, so every request gets 401")
    end

    :ok
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp parse_entry(entry) do
    with [name, scopes, hex] <- String.split(entry, ":"),
         true <- Regex.match?(~r/^[A-Za-z0-9_.-]+$/, name),
         scopes = String.split(scopes, "+"),
         true <- Enum.all?(scopes, &(&1 in @scopes)),
         {:ok, <<_::binary-size(32)>> = hash} <- Base.decode16(hex, case: :mixed) do
      {:ok, %{name: name, scopes: Enum.uniq(scopes), hash: hash}}
    else
      _ -> :error
    end
  end

  defp valid_tokens, do: configured() |> parse() |> elem(0)

  defp configured, do: Application.get_env(:deployex_web, DeployexWeb.AgentApi, [])[:tokens]
end
