defmodule Deployer.Status.Logo do
  @moduledoc """
  Reads the logo of a monitored application so it can be shown in the UI.

  The logo is fetched over RPC from the monitored node, at
  `priv/static/images/logo.svg` inside the application's own `priv`
  directory, and returned as a base64 `data:` URI ready to be used as an
  `<img>` source.

  For a single-app release the logo is read from the application named after
  the catalog entry. For a Phoenix umbrella the logo usually lives in the
  `<name>_web` child, whose atom is not known on this node, so the loaded
  applications on the monitored node are inspected over RPC and the `<name>_web`
  child is probed for the logo.

  Lookup is best effort and never fails: an unknown application, an
  unreachable node or a missing file all yield `nil`, so a missing logo
  never prevents an application from being rendered. The caller is free to
  cache that answer, which keeps an umbrella from asking every application
  for a logo it does not have on every refresh.
  """

  alias Foundation.Rpc

  @rpc_timeout 1_000

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Return the logo of the application `name` running on `node` as a base64
  `data:` URI.

  Always answers. Returns `{:ok, nil}` when the application is unknown, the
  node did not reply or the node has no `logo.svg`, so the caller can cache
  the result and stop asking for a logo that is not there.
  """
  @spec image(node :: node(), name :: String.t()) :: {:ok, String.t() | nil}
  def image(node, name) do
    with {:ok, app} <- existing_atom(name),
         {:ok, value} when value != nil <- logo_from_app(node, app) do
      {:ok, value}
    else
      # The name is not a known application on this node, so it is not a
      # catalog entry: do not reach the remote node for an umbrella probe.
      {:error, :unknown} ->
        {:ok, nil}

      # The main application has no logo: try the `<name>_web` umbrella child,
      # whose atom is not known on this node and is discovered from the loaded
      # applications on the monitored node.
      _ ->
        logo_from_elixir_umbrella(node, name)
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  # An umbrella's logo usually lives in the `<name>_web` child, whose atom is
  # not known on this node. The loaded applications on the monitored node are
  # the source of truth for the real child atom, so no local atom conversion is
  # needed: the atoms come back in the RPC response.
  defp logo_from_elixir_umbrella(node, name) do
    with apps when is_list(apps) <-
           Rpc.call(node, :application, :loaded_applications, [], @rpc_timeout),
         [{app, _descr, _version}] <-
           Enum.filter(apps, fn {app, _descr, _version} -> "#{app}" == "#{name}_web" end) do
      logo_from_app(node, app)
    else
      _err ->
        {:ok, nil}
    end
  end

  defp logo_from_app(node, app) do
    with {:ok, priv_dir} <- app_priv_dir(node, app),
         path <- logo_path(priv_dir),
         {:ok, binary} <- Rpc.call(node, :file, :read_file, [path], @rpc_timeout) do
      {:ok, "data:image/svg+xml;base64," <> Base.encode64(binary)}
    else
      _ -> {:ok, nil}
    end
  end

  # The application name only maps to an atom when the application is known
  # to this node, so an unknown name is a normal miss rather than a failure.
  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> {:error, :unknown}
  end

  defp app_priv_dir(node, app) do
    case Rpc.call(node, :code, :priv_dir, [app], @rpc_timeout) do
      priv_dir when is_list(priv_dir) ->
        {:ok, to_string(priv_dir)}

      _err ->
        {:error, :no_priv}
    end
  end

  defp logo_path(priv_dir) do
    Path.join([priv_dir, "static", "images", "logo.svg"])
  end
end
