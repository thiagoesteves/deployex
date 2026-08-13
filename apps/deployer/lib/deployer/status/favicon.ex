defmodule Deployer.Status.Favicon do
  @moduledoc """
  Reads the logo of a monitored application from the first Phoenix endpoint
  it can find on the node. Returns a base64 data URI when the node has a
  `priv/static/logo.svg` or `priv/static/favicon.ico` file, otherwise `nil`.
  """

  alias Foundation.Rpc

  @rpc_timeout 1_000
  @endpoint_suffix "Endpoint"

  # Prefer the SVG logo because a favicon is usually too small for the dashboard
  # card; fall back to the ICO if that is all the app ships.
  @candidates [
    {"logo.svg", "image/svg+xml"},
    {"favicon.ico", "image/x-icon"}
  ]

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Return the logo as a `data:` URI for the node, or `nil` when no logo
  is found. Returns `:error` when the node is unreachable.
  """
  @spec image(node :: node()) :: {:ok, String.t() | nil} | :error
  def image(node) do
    case Rpc.call(node, :erlang, :registered, [], @rpc_timeout) do
      names when is_list(names) ->
        favicon =
          names
          |> Enum.filter(&endpoint_module?/1)
          |> Enum.find_value(&read_favicon(node, &1))

        {:ok, favicon}

      _ ->
        :error
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp endpoint_module?(name) do
    case Atom.to_string(name) do
      "Elixir." <> module -> String.ends_with?(module, @endpoint_suffix)
      _ -> false
    end
  end

  defp read_favicon(node, module) do
    with beam_path when is_binary(beam_path) <-
           Rpc.call(node, :code, :which, [module], @rpc_timeout),
         priv_dir = Path.join([Path.dirname(Path.dirname(beam_path)), "priv"]) do
      Enum.find_value(@candidates, fn {file, mime} ->
        favicon_path = Path.join([priv_dir, "static", file])

        case Rpc.call(node, :file, :read_file, [favicon_path], @rpc_timeout) do
          {:ok, binary} -> "data:#{mime};base64," <> Base.encode64(binary)
          _ -> nil
        end
      end)
    else
      _ -> nil
    end
  end
end
