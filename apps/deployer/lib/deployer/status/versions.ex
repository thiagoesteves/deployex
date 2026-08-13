defmodule Deployer.Status.Versions do
  @moduledoc """
  Discovers the Erlang, Elixir and Phoenix versions a node is running.
  """

  alias Foundation.Rpc

  @rpc_timeout 1_000

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Return the OTP release version the node is running, or nil when it is unreachable.
  """
  @spec otp_version(node :: node()) :: {:ok, String.t() | nil} | {:error, nil}
  def otp_version(node) do
    rpc_string(node, :erlang, :system_info, [:otp_release])
  end

  @doc """
  Return the Elixir version the node is running, or nil when it is unreachable or not loaded.
  """
  @spec elixir_version(node :: node()) :: {:ok, String.t() | nil} | {:error, nil}
  def elixir_version(node) do
    rpc_string(node, Application, :spec, [:elixir, :vsn])
  end

  @doc """
  Return the Phoenix version the node is running, or nil when it is unreachable or not loaded.
  """
  @spec phoenix_version(node :: node()) :: {:ok, String.t() | nil} | {:error, nil}
  def phoenix_version(node) do
    rpc_string(node, Application, :spec, [:phoenix, :vsn])
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp rpc_string(node, module, function, args) do
    case Rpc.call(node, module, function, args, @rpc_timeout) do
      {:badrpc, {:EXIT, {:undef, _}}} -> {:ok, nil}
      {:badrpc, _} -> {:error, nil}
      version -> {:ok, "#{version}"}
    end
  end
end
