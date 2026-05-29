defmodule Foundation.Certificates.DNSProvider do
  @moduledoc """
  Behaviour for DNS providers that handle ACME DNS-01 challenges.

  This allows the system to support different DNS providers:
  - Route53 (AWS)
  - Cloudflare
  - Mock (for testing)

  Each provider handles DNS record management for ACME certificate validation.
  """

  @doc """
  Create or update a TXT record for DNS-01 challenge.

  ## Parameters
  - `name`: Full DNS record name (e.g., "_acme-challenge.example.com.")
  - `txt_value`: TXT record value
  - `opts`: Provider-specific options (like zone, ttl)

  ## Returns
  - `:ok`: Record created/updated successfully
  - `{:error, reason}`: Failed to create/update record
  """
  @callback upsert_txt_record(
              name :: String.t(),
              txt_value :: String.t(),
              options :: keyword()
            ) :: :ok | {:error, any()}
end
