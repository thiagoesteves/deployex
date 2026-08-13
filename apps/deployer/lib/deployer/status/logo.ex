defmodule Deployer.Status.Logo do
  @moduledoc """
  Reads the logo of a monitored application so it can be shown in the UI.

  The logo is fetched over RPC from the monitored node, at
  `priv/static/images/logo.svg` inside the application's own `priv`
  directory, and returned as a base64 `data:` URI ready to be used as an
  `<img>` source.

  Lookup is best effort: an unknown application, an unreachable node or a
  missing file all yield `nil` rather than an error, so a missing logo
  never prevents the application from being rendered.
  """

  alias Foundation.Rpc

  @rpc_timeout 1_000

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Return the logo of the application `name` running on `node` as a base64
  `data:` URI.

  Returns `{:ok, nil}` when the application is unknown, the node is
  unreachable or the node has no `logo.svg`.
  """
  @spec image(node :: node(), name :: String.t()) :: {:ok, String.t() | nil}
  def image(node, name) do
    with {:ok, app} <- existing_atom(name),
         {:ok, priv_dir} <- app_priv_dir(node, app),
         path <- logo_path(priv_dir),
         {:ok, binary} <- Rpc.call(node, :file, :read_file, [path], @rpc_timeout) do
      {:ok, "data:image/svg+xml;base64," <> Base.encode64(binary)}
    else
      _ -> {:ok, nil}
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  # The application name only maps to an atom when the application is known
  # to this node, so an unknown name is a normal miss rather than a failure.
  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  defp app_priv_dir(node, app) do
    case Rpc.call(node, :code, :priv_dir, [app], @rpc_timeout) do
      priv_dir when is_list(priv_dir) ->
        {:ok, to_string(priv_dir)}

      _err ->
        :error
    end
  end

  defp logo_path(priv_dir) do
    Path.join([priv_dir, "static", "images", "logo.svg"])
  end
end
