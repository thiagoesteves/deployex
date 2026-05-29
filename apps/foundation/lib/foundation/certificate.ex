defmodule Foundation.Certificate do
  @moduledoc """
  GenServer responsible for bootstrapping and coordinating certificate managers
  across all registered applications.
  """

  use GenServer

  import Foundation.Macros

  alias Foundation.Certificates.Manager.Supervisor

  require Logger

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Logger.info("Initializing Certificate Server")
    {:ok, %{}, {:continue, :start_certificate_manager}}
  end

  @impl true
  def handle_continue(:start_certificate_manager, state) do
    initialize_certificate_manager()
    {:noreply, state}
  end

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

  if_not_test do
    alias Foundation.Catalog

    defp initialize_certificate_manager do
      Catalog.applications()
      |> Enum.each(fn
        %{certificates: []} ->
          :ok

        %{name: app_name, certificates: certificates} ->
          Enum.each(
            certificates,
            &Supervisor.start_certificate_manager(app_name, &1)
          )
      end)
    end
  else
    defp initialize_certificate_manager, do: :ok
  end
end
