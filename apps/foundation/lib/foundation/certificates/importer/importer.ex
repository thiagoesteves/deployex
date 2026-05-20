defmodule Foundation.Certificates.Importer do
  @moduledoc """
  Behaviour for certificate importers responsible for deploying issued TLS
  certificates to their final destination after ACME issuance or renewal.

  ## Built-in implementations (Examples)

  - `Foundation.Certificates.Importer.Route53` — uploads to AWS Certificate Manager
  - `Foundation.Certificates.Importer.Filesystem` — writes PEM files to disk
  - `Foundation.Certificates.Importer.Mock` — no-op used in tests
  """

  @doc """
  Deploy a certificate to the importer's target destination.

  Called by `Foundation.Certificates.Manager` after a certificate has been
  successfully issued or renewed.

  ## Parameters

  - `app_name` — identifier of the application that owns the certificate.
  - `certificate_pem` — the end-entity certificate in PEM format.
  - `chain_certificate_pem` — the intermediate CA chain in PEM format.
  - `private_key_pem` — the private key in PEM format. Handle with care; avoid logging.
  - `options` — provider-specific options map passed through from the certificate config.

  ## Returns

  - `:ok` — certificate was successfully delivered to the target.
  - `{:error, reason}` — delivery failed; `reason` should describe the failure.
  """
  @callback export_certificate(
              app_name :: String.t(),
              certificate_pem :: String.t(),
              chai_certificate_pem :: String.t(),
              private_key_pem :: String.t(),
              options :: map()
            ) :: :ok | {:error, any()}
end
