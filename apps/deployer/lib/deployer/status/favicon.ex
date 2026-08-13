defmodule Deployer.Status.Favicon do
  @moduledoc """
  Reads the favicon of a monitored application from the first Phoenix endpoint
  it can find on the node. Returns a base64 data URI when the node has a
  `priv/static/favicon.ico` file, otherwise `nil`.
  """

  alias Foundation.Rpc

  @rpc_timeout 1_000
  @favicon "favicon.ico"
  @endpoint_suffix "Endpoint"

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Return the favicon as a `data:` URI for the node, or `nil` when no favicon
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
         priv_dir = Path.join([Path.dirname(Path.dirname(beam_path)), "priv"]),
         favicon_path = Path.join([priv_dir, "static", @favicon]),
         {:ok, binary} <- Rpc.call(node, :file, :read_file, [favicon_path], @rpc_timeout) do
      "data:image/x-icon;base64," <> Base.encode64(binary)
    else
      _ -> nil
    end
  end
end
