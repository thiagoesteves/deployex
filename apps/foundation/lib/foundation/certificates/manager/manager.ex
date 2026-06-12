defmodule Foundation.Certificates.Manager do
  @moduledoc """
  GenServer that manages the full lifecycle of a TLS certificate for a single
  application: initial issuance, periodic renewal checks, and deployment.

  On startup it immediately checks whether the application's certificate needs to
  be issued or renewed (`:check_and_renew` continue). Afterwards it reschedules
  itself every `certificate_check_interval_ms` milliseconds to repeat the check.

  The issuance pipeline is:
    1. Create/reuse an ACME account and order.
    2. Satisfy DNS-01 challenges via the configured `dns_provider`.
    3. Poll DNS until the TXT records have propagated.
    4. Ask the ACME provider to validate and finalize the order.
    5. Export the resulting certificate chain via the configured `importer`.
    6. Persist metadata to the catalog.

  Renewal is skipped when a valid certificate already exists unless
  `force_renewal: true` is passed to `request_and_import_certificate/2`.
  """

  use GenServer

  alias Foundation.Catalog
  alias Foundation.Network

  require Logger

  @type t() :: %__MODULE__{
          app_name: String.t(),
          domains: [String.t()],
          certificate_check_interval_ms: non_neg_integer(),
          dns_propagation_timeout_ms: non_neg_integer(),
          dns_check_interval_ms: non_neg_integer(),
          renew_before_days: non_neg_integer(),
          dns_provider: atom(),
          dns_options: map(),
          acme_provider: atom(),
          acme_options: map(),
          importer: atom(),
          importer_options: map()
        }

  defstruct [
    :app_name,
    :domains,
    :certificate_check_interval_ms,
    :dns_propagation_timeout_ms,
    :dns_check_interval_ms,
    :renew_before_days,
    :dns_provider,
    :dns_options,
    :acme_provider,
    :acme_options,
    :importer,
    :importer_options
  ]

  @default_nameservers ["8.8.8.8", "1.1.1.1"]

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(%__MODULE__{app_name: app_name} = config) do
    GenServer.start_link(__MODULE__, config, name: server_name(app_name))
  end

  @impl true
  def init(%__MODULE__{app_name: app_name} = state) do
    Logger.info("Initializing Certificate Manager Renewal for app: #{app_name}")
    {:ok, state, {:continue, :check_and_renew}}
  end

  @impl true
  def handle_continue(:check_and_renew, state) do
    case request_and_import_certificate(state) do
      {:ok, certificate} ->
        Logger.info(
          "Certificate check completed successfully for app: #{state.app_name}, domains: #{inspect(certificate.domains)}"
        )

      {:error, reason} ->
        Logger.error("Certificate renewal check failed: #{inspect(reason)}")
    end

    _ = Process.send_after(self(), :check_and_renew, state.certificate_check_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_and_renew, state) do
    {:noreply, state, {:continue, :check_and_renew}}
  end

  ### ==========================================================================
  ### Public Functions
  ### ==========================================================================

  def server_name(app_name), do: String.to_atom("certificate_manager_" <> "#{app_name}")

  @doc """
  Generate and deploy a certificate for the given domains.
  """
  @spec request_and_import_certificate(__MODULE__.t(), boolean()) ::
          {:ok, map()} | {:error, any()}
  def request_and_import_certificate(state, force_renewal \\ false) do
    Logger.info(
      "Generating certificate for app: #{state.app_name} - #{inspect(state.domains)} using strategy: #{state.acme_provider}"
    )

    existing_cert = Catalog.certificate(state.app_name)

    case {existing_cert, force_renewal} do
      {%{certificate_pem: nil}, _} ->
        Logger.info("No domain certificate exists, creating new one for #{state.app_name}")
        new_certificate = Catalog.Certificate.new(state)
        generate_and_store_acme_certificate(state, new_certificate)

      {cert, true} ->
        Logger.info(
          "Certificate exists but force renewal requested, updating existing certificate"
        )

        generate_and_store_acme_certificate(state, cert)

      {cert, false} ->
        if Catalog.Certificate.valid?(cert, state.renew_before_days) do
          Logger.info(
            "Using existing valid certificate for app: #{state.app_name} - #{inspect(state.domains)}"
          )

          {:ok, cert}
        else
          Logger.info("Certificate exists but is invalid, updating existing certificate")
          generate_and_store_acme_certificate(state, cert)
        end
    end
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp generate_and_store_acme_certificate(
         %__MODULE__{app_name: app_name, importer: importer, importer_options: importer_options} =
           cert_config,
         existing_cert
       ) do
    with {:ok, cert_chain_pem, private_key_pem} <- generate_acme_certificate_data(cert_config),
         {:ok, attrs} <- build_meta_certificate(cert_config, cert_chain_pem, private_key_pem),
         :ok <-
           importer.export_certificate(
             app_name,
             attrs.certificate_pem,
             attrs.chain_certificate_pem,
             private_key_pem,
             importer_options
           ) do
      Catalog.certificate_update(app_name, struct(existing_cert, attrs))
    end
  end

  defp generate_acme_certificate_data(
         %__MODULE__{
           app_name: app_name,
           domains: domains,
           acme_provider: acme_provider,
           acme_options: acme_options
         } =
           cert_config
       ) do
    with {:ok, account_key} <- acme_provider.setup_account(app_name, acme_options),
         {:ok, order} <- acme_provider.create_order(app_name, domains, account_key),
         {:ok, challenges} <- acme_provider.get_dns_challenges(app_name, order, account_key),
         :ok <- upsert_dns_records(cert_config, challenges),
         :ok <- wait_for_dns_propagation(cert_config, challenges),
         :ok <- acme_provider.start_challenge_validation(app_name, challenges, account_key),
         :ok <- acme_provider.wait_for_validation(app_name, challenges, account_key, acme_options),
         {:ok, cert_chain_pem, private_key_pem} <-
           acme_provider.finalize_certificate(app_name, order, account_key, acme_options) do
      {:ok, cert_chain_pem, private_key_pem}
    else
      error ->
        Logger.error("ACME certificate generation for #{app_name}, reason: #{inspect(error)}")
        error
    end
  end

  defp upsert_dns_records(
         %__MODULE__{app_name: app_name, dns_provider: dns_provider, dns_options: dns_options},
         challenges
       ) do
    Logger.info("Creating DNS challenge records for #{app_name}")

    results =
      Enum.map(challenges, fn challenge ->
        dns_provider.upsert_txt_record(
          challenge.record_name,
          challenge.record_value,
          dns_options
        )
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        Logger.info("Successfully created all DNS challenge records for #{app_name}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to create DNS challenge for #{app_name} reason: #{inspect(reason)}")
        {:error, {:dns_record_creation_failed, reason}}
    end
  end

  defp wait_for_dns_propagation(cert_config, challenges) do
    Logger.info("Waiting for DNS propagation for #{cert_config.app_name}")

    max_attempts =
      div(
        cert_config.dns_propagation_timeout_ms,
        cert_config.dns_check_interval_ms
      )

    wait_for_propagation_attempts(
      cert_config,
      challenges,
      max_attempts,
      cert_config.dns_check_interval_ms
    )
  end

  defp wait_for_propagation_attempts(cert_config, _challenges, 0, _interval) do
    Logger.error("DNS propagation timeout for #{cert_config.app_name}")
    {:error, :dns_propagation_timeout}
  end

  defp wait_for_propagation_attempts(
         cert_config,
         challenges,
         attempts_left,
         interval
       ) do
    all_propagated =
      Enum.all?(challenges, fn challenge ->
        case check_propagation(challenge.record_name, challenge.record_value) do
          :ok -> true
          {:error, :not_propagated} -> false
        end
      end)

    if all_propagated do
      Logger.info("DNS propagation complete for #{cert_config.app_name}")
      :ok
    else
      Logger.info(
        "DNS not yet propagated for #{cert_config.app_name}, waiting #{interval}ms (#{attempts_left} attempts left)"
      )

      Process.sleep(interval)
      wait_for_propagation_attempts(cert_config, challenges, attempts_left - 1, interval)
    end
  end

  defp build_meta_certificate(cert_config, cert_chain_pem, private_key_pem) do
    case Catalog.Certificate.metadata_from_cert_pem(cert_chain_pem) do
      {:ok, meta} ->
        {certificate, chain_certificate} =
          Catalog.Certificate.split_certificate_chain(cert_chain_pem)

        attrs = %{
          domain: cert_config.domains,
          certificate_pem: certificate,
          private_key_pem: private_key_pem,
          chain_certificate_pem: chain_certificate,
          issuer: meta.issuer,
          valid_from: meta.valid_from,
          valid_until: meta.valid_until,
          updated_at: DateTime.utc_now()
        }

        {:ok, attrs}

      {:error, reason} ->
        {:error, {:invalid_certificate_metadata, reason}}
    end
  end

  defp check_propagation(name, expected_value) do
    lookup_name = String.trim_trailing(name, ".")
    domain_charlist = String.to_charlist(lookup_name)

    case Network.lookup(domain_charlist, :in, :txt, nameservers: public_nameservers()) do
      [] ->
        {:error, :not_propagated}

      txt_records ->
        if record_matches?(txt_records, expected_value) do
          :ok
        else
          {:error, :not_propagated}
        end
    end
  rescue
    _ -> {:error, :not_propagated}
  end

  defp record_matches?(txt_records, expected_value) do
    Enum.any?(txt_records, fn record ->
      record_string = normalize_record(record)

      String.contains?(record_string, expected_value) or
        String.contains?(record_string, "\"#{expected_value}\"")
    end)
  end

  defp normalize_record(record) when is_list(record), do: List.to_string(record)
  defp normalize_record(record), do: inspect(record)

  # Use public resolvers to avoid stale NXDOMAIN from VPC/local caching resolvers
  defp public_nameservers do
    @default_nameservers
    |> Enum.map(fn ip ->
      {:ok, parsed} = ip |> String.to_charlist() |> :inet.parse_address()
      {parsed, 53}
    end)
  end
end
