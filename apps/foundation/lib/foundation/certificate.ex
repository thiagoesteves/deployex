defmodule Foundation.Certificate do
  @moduledoc """
  Provides functions for bootstrapping and managing certificate managers
  across all registered applications.

  On application startup, `initialize_certificate_manager/0` is called to
  start a certificate manager for each application that declares certificates
  in its catalog entry. Individual managers can also be started or stopped
  on demand via `start_certificate_manager/2` and `stop_certificate_manager/1`.
  """

  require Logger

  alias Foundation.Catalog
  alias Foundation.Certificates.Manager.Supervisor

  ### ==========================================================================
  ### Public Functions
  ### ==========================================================================

  @spec start_certificate_manager(
          app_name :: String.t(),
          certificates :: list(Foundation.Yaml.Certificate.t())
        ) :: :ok
  def start_certificate_manager(app_name, certificates) do
    Enum.each(certificates, &Supervisor.start_certificate_manager(app_name, &1))
  end

  @spec stop_certificate_manager(app_name :: String.t()) :: :ok
  def stop_certificate_manager(app_name) do
    Supervisor.stop_certificate_manager(app_name)
  end

  @doc """
  Write the stored certificate and private key of an application to disk.

  The certificate is written as a full chain, the leaf followed by the intermediates, which
  is what a server expects when it has to present the chain itself rather than receive it
  from a load balancer.

  Files are created with mode 0600 for the private key and 0644 for the certificate, and
  the parent directories are created if missing.

  DeployEx runs as the unprivileged `deployex` user, so the destination has to be writable
  by it. A path such as `/etc/ssl` is root owned by default and needs granting first, for
  example:

      install -d -o deployex -g deployex -m 0750 /etc/ssl/myapp

  Returns `{:error, :not_found}` when no certificate has been issued yet, and
  `{:error, {:write_failed, path, reason}}` when a file cannot be written, which is most
  often `:eacces` for exactly that reason.

  ## Examples

      iex> Foundation.Certificate.export_to_files("nerveshub", "/etc/ssl/host.pem", "/etc/ssl/host-key.pem")
      {:ok, %{certificate_path: "/etc/ssl/host.pem", private_key_path: "/etc/ssl/host-key.pem"}}
  """
  @spec export_to_files(
          app_name :: String.t(),
          certificate_path :: String.t(),
          private_key_path :: String.t()
        ) :: {:ok, map()} | {:error, any()}
  def export_to_files(app_name, certificate_path, private_key_path) do
    case Catalog.certificate(app_name) do
      %Catalog.Certificate{certificate_pem: cert, private_key_pem: key} = certificate
      when is_binary(cert) and is_binary(key) ->
        write_certificate_files(certificate, certificate_path, private_key_path)

      _ ->
        Logger.error("No certificate stored for app: #{app_name}, nothing to export")
        {:error, :not_found}
    end
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp write_certificate_files(certificate, certificate_path, private_key_path) do
    # Leaf first, then the intermediates. A server presenting its own chain needs both,
    # and the order matters to some clients
    full_chain =
      [certificate.certificate_pem, certificate.chain_certificate_pem]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map_join("\n", &String.trim/1)
      |> Kernel.<>("\n")

    with :ok <- write_file(certificate_path, full_chain, 0o644),
         :ok <- write_file(private_key_path, certificate.private_key_pem, 0o600) do
      Logger.info(
        "Exported certificate to: #{certificate_path} and private key to: #{private_key_path}"
      )

      {:ok, %{certificate_path: certificate_path, private_key_path: private_key_path}}
    end
  end

  defp write_file(path, content, mode) do
    with :ok <- path |> Path.dirname() |> File.mkdir_p(),
         :ok <- File.write(path, content),
         :ok <- File.chmod(path, mode) do
      :ok
    else
      {:error, reason} ->
        # :eacces here almost always means the directory is not writable by the deployex
        # user, see the note on export_to_files/3
        Logger.error("Error while writing #{path}, reason: #{inspect(reason)}")
        {:error, {:write_failed, path, reason}}
    end
  end

  @spec initialize_certificate_manager() :: :ok
  def initialize_certificate_manager do
    Foundation.Catalog.applications()
    |> Enum.each(fn
      %{certificates: []} ->
        :ok

      %{name: app_name, certificates: certificates} ->
        Enum.each(
          certificates,
          &Supervisor.start_certificate_manager(app_name, &1)
        )
    end)

    :ok
  end
end
