defmodule Foundation.Certificate do
  @moduledoc """
  Provides functions for bootstrapping and managing certificate managers
  across all registered applications.

  On application startup, `initialize_certificate_manager/0` is called to
  start a certificate manager for each application that declares certificates
  in its catalog entry. Individual managers can also be started or stopped
  on demand via `start_certificate_manager/2` and `stop_certificate_manager/1`.
  """

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

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

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
