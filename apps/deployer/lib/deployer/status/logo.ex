defmodule Deployer.Status.Logo do
  @moduledoc """
  Reads the logo of a monitored application so it can be shown in the UI.

  The logo is fetched over RPC from the monitored node, at
  `priv/static/images/logo.svg` inside the application's own `priv`
  directory, and returned as a base64 `data:` URI ready to be used as an
  `<img>` source.

  Lookup is best effort and never prevents an application from being
  rendered. It distinguishes an application that answered and has no logo,
  which is a definitive answer, from a lookup that could not be performed
  because the node did not reply, so that a transient failure is not
  remembered as a missing logo.
  """

  alias Foundation.Rpc

  @rpc_timeout 1_000

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Return the logo of the application `name` running on `node` as a base64
  `data:` URI.

  Returns `{:ok, nil}` when the node answered but has no `logo.svg`, which
  is a definitive answer and safe for the caller to cache.

  Returns `:error` when the question could not be answered at all, because
  the name is not a known application or the node did not reply. The caller
  is expected to treat this as "unknown for now" and ask again later rather
  than remembering the absence of a logo.
  """
  @spec image(node :: node(), name :: String.t()) :: {:ok, String.t() | nil} | :error
  def image(node, name) do
    with {:ok, app} <- existing_atom(name),
         {:ok, priv_dir} <- app_priv_dir(node, app),
         path <- logo_path(priv_dir),
         {:ok, binary} <- Rpc.call(node, :file, :read_file, [path], @rpc_timeout) do
      {:ok, "data:image/svg+xml;base64," <> Base.encode64(binary)}
    else
      :error -> :error
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
