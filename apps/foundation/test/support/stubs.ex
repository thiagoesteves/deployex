defmodule Foundation.Fixture.Stubs do
  @moduledoc false

  defmodule DNSProvider do
    @moduledoc false
    @behaviour Foundation.Certificates.DNSProvider

    @impl true
    def upsert_txt_record(_name, _value, _opts), do: :ok
  end

  defmodule FailingDNSProvider do
    @moduledoc false
    @behaviour Foundation.Certificates.DNSProvider

    @impl true
    def upsert_txt_record(_name, _value, _opts), do: {:error, :dns_failure}
  end

  defmodule ACMEProvider do
    @moduledoc false
    @behaviour Foundation.Certificates.ACMEProvider

    @impl true
    def setup_account(_app, _opts), do: {:ok, "account_key"}
    @impl true
    def create_order(_app, _domains, _key), do: {:ok, %{order: "order"}}
    @impl true
    def get_dns_challenges(_app, _order, _key),
      do: {:ok, [%{record_name: "_acme.example.com.", record_value: "token123", challenge: []}]}

    @impl true
    def start_challenge_validation(_app, _challenges, _key), do: :ok
    @impl true
    def wait_for_validation(_app, _challenges, _key, _options), do: :ok

    @impl true
    def finalize_certificate(_app, _order, _key, _opts),
      do: {:ok, cert_chain_pem(), "private_key_pem"}

    # Minimal self-signed PEM understood by Catalog.Certificate.metadata_from_cert_pem/1.
    # Tests that need real PEM parsing should substitute their own fixture.
    def cert_chain_pem do
      # Return a two-entry chain so split_certificate_chain has something to work with.
      """
      -----BEGIN CERTIFICATE-----
      FAKE_CERT_DATA
      -----END CERTIFICATE-----
      -----BEGIN CERTIFICATE-----
      FAKE_CHAIN_DATA
      -----END CERTIFICATE-----
      """
    end
  end

  defmodule FailingACMEProvider do
    @moduledoc false
    @behaviour Foundation.Certificates.ACMEProvider

    @impl true
    def setup_account(_app, _opts), do: {:error, :acme_setup_failed}
    @impl true
    def create_order(_app, _domains, _key), do: {:error, :order_failed}
    @impl true
    def get_dns_challenges(_app, _order, _key), do: {:error, :challenge_failed}
    @impl true
    def start_challenge_validation(_app, _challenges, _key), do: {:error, :validation_failed}
    @impl true
    def wait_for_validation(_app, _challenges, _key, _options), do: {:error, :validation_timeout}
    @impl true
    def finalize_certificate(_app, _order, _key, _opts), do: {:error, :finalization_failed}
  end

  defmodule Importer do
    @moduledoc false
    @behaviour Foundation.Certificates.Importer

    @impl true
    def export_certificate(_app, _cert, _chain, _key, _opts), do: :ok
  end
end
