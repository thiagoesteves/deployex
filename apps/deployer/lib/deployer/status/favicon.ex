defmodule Deployer.Status.Favicon do
  @moduledoc """
  Reads the icon of a monitored application from its `priv` directory.
  It looks for `logo.*` or `favicon.*` directly under `priv` or one level
  below (e.g. `priv/static/`) and returns the first match as a base64
  `data:` URI, otherwise `nil`.
  """

  alias Foundation.Rpc

  @rpc_timeout 1_000

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Return the icon as a `data:` URI for the node, or `nil` when no icon
  is found. Returns `:error` when the node is unreachable.
  """
  @spec image(node :: node(), app :: String.t()) :: {:ok, String.t() | nil} | :error
  def image(node, app) do
    case Rpc.call(node, :code, :priv_dir, [String.to_atom(app)], @rpc_timeout) do
      priv_dir when is_binary(priv_dir) or is_list(priv_dir) ->
        priv_dir = to_string(priv_dir)

        with patterns = icon_patterns(priv_dir),
             matches when is_list(matches) and matches != [] <-
               Rpc.call(node, :filelib, :wildcard, [patterns], @rpc_timeout),
             path <- choose_match(matches),
             {:ok, binary} <- Rpc.call(node, :file, :read_file, [path], @rpc_timeout) do
          {:ok, "data:#{mime(path)};base64," <> Base.encode64(binary)}
        else
          _ -> {:ok, nil}
        end

      _ ->
        :error
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp icon_patterns(priv_dir) do
    Enum.flat_map([priv_dir, Path.join(priv_dir, "*")], fn dir ->
      Enum.map(["logo.*", "favicon.*"], fn file ->
        Path.join([dir, file]) |> String.to_charlist()
      end)
    end)
  end

  defp choose_match(matches) do
    matches
    |> Enum.map(&to_string/1)
    |> Enum.min_by(&match_score/1)
    |> String.to_charlist()
  end

  # Lower score is better; prefer logo.svg, then favicon.ico, then other svg/ico
  defp match_score(path) do
    case {Path.basename(path), Path.extname(path)} do
      {"logo.svg", _} -> 0
      {"favicon.ico", _} -> 1
      {_, ".svg"} -> 2
      {_, ".ico"} -> 3
      _ -> 100
    end
  end

  defp mime(path) do
    case Path.extname(to_string(path)) do
      ".svg" -> "image/svg+xml"
      ".ico" -> "image/x-icon"
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      _ -> "application/octet-stream"
    end
  end
end
