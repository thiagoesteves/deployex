defmodule Foundation.Certificates.Manager.Supervisor do
  @moduledoc """
  DynamicSupervisor that owns one `Foundation.Certificates.Manager` process per
  application certificate.

  Each manager is started on demand via `start_certificate_manager/2` and
  supervised with a `:transient` restart strategy, meaning it is only restarted
  if it terminates abnormally. Only certificates of `type: :domains` are
  accepted; all other types are silently ignored.

  Typical call site is `Foundation.Certificate` during system initialization,
  but managers can also be started or stopped at runtime.
  """

  use DynamicSupervisor

  alias Foundation.Certificates.Manager

  ### ==========================================================================
  ### DynamicSupervisor Callbacks
  ### ==========================================================================
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 20)
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================
  def start_certificate_manager(app_name, %{type: :domains} = app_certificate) do
    spec = %{
      id: Manager,
      start: {Manager, :start_link, [app_cert_to_manager_cert(app_name, app_certificate)]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def start_certificate_manager(_app_name, _certificate), do: :ignore

  def stop_certificate_manager(app_name) do
    case app_name |> Manager.server_name() |> Process.whereis() do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp app_cert_to_manager_cert(app_name, cert) do
    %Manager{
      app_name: app_name,
      domains: cert.domains,
      certificate_check_interval_ms: cert.certificate_check_interval_ms,
      dns_propagation_timeout_ms: cert.dns_propagation_timeout_ms,
      dns_check_interval_ms: cert.dns_check_interval_ms,
      renew_before_days: cert.renew_before_days,
      dns_provider: cert.dns_provider,
      dns_options: to_map(cert.dns_options),
      acme_provider: cert.acme_provider,
      acme_options: to_map(cert.acme_options),
      importer: cert.importer,
      importer_options: to_map(cert.importer_options)
    }
  end

  defp to_map(value) when is_struct(value), do: Map.from_struct(value)
  defp to_map(value) when is_map(value), do: value
end
