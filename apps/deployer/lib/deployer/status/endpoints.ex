defmodule Deployer.Status.Endpoints do
  @moduledoc """
  Discovers the URLs an application is serving on.

  Phoenix registers the supervisor of every endpoint under the endpoint module name itself, so
  the registered names of a node already list its endpoints. Each candidate is then asked for
  its own url, which resolves scheme, host and port from the configuration the application is
  actually running with, and at the same time confirms the module really is an endpoint.

  Only endpoints following the `*.Endpoint` naming convention are discovered, and applications
  that serve no Phoenix endpoint report no url.
  """

  alias Foundation.Rpc

  @rpc_timeout 1_000
  @endpoint_suffix "Endpoint"

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Return the urls the node is serving on, empty when it serves none.
  Returns `:error` when the node is unreachable.
  """
  @spec urls(node :: node()) :: {:ok, [String.t()]} | :error
  def urls(node) do
    case endpoint_candidates(node) do
      {:ok, names} ->
        urls =
          names
          |> Enum.flat_map(&endpoint_url(node, &1))
          |> Enum.uniq()
          |> Enum.sort()

        {:ok, urls}

      :error ->
        :error
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp endpoint_candidates(node) do
    case Rpc.call(node, :erlang, :registered, [], @rpc_timeout) do
      names when is_list(names) -> {:ok, Enum.filter(names, &endpoint_module?/1)}
      _unreachable -> :error
    end
  end

  defp endpoint_module?(name) do
    case Atom.to_string(name) do
      "Elixir." <> module -> String.ends_with?(module, @endpoint_suffix)
      _erlang_registered_name -> false
    end
  end

  defp endpoint_url(node, module) do
    case Rpc.call(node, module, :url, [], @rpc_timeout) do
      url when is_binary(url) -> [url]
      _not_an_endpoint -> []
    end
  end
end
