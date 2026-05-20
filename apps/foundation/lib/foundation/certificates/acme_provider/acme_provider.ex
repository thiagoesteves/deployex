defmodule Foundation.Certificates.ACMEProvider do
  @moduledoc """
  Behaviour for ACME client implementations.

  This allows the system to support different ACME clients:
  - ExAcme (current Elixir implementation)
  - Lego (Go-based ACME client)
  - Certbot (Python-based ACME client)
  - ACME.sh (Shell-based ACME client)

  Each client handles the ACME protocol specifics while providing
  a unified interface for certificate generation.
  """

  @type account_key :: any()
  @type order :: any()
  @type challenge :: any()
  @type certificate_chain :: String.t()
  @type private_key_pem :: String.t()

  @doc """
  Setup and register an ACME account.

  ## Parameters
  - `opts`: Client-specific configuration options

  ## Returns
  - `{:ok, account_key}`: Successfully setup account
  - `{:error, reason}`: Failed to setup account
  """
  @callback setup_account(app_name :: String.t(), opts :: map()) ::
              {:ok, account_key()} | {:error, any()}

  @doc """
  Create a new ACME order for the given domains.

  ## Parameters
  - `app_name`: identifier of the requesting application, used for logging
  and correlation.
  - `domains`: List of domains to include in the certificate
  - `account_key`: The ACME account key

  ## Returns
  - `{:ok, order}`: Successfully created order
  - `{:error, reason}`: Failed to create order
  """
  @callback create_order(
              app_name :: String.t(),
              domains :: [String.t()],
              account_key :: account_key()
            ) :: {:ok, order()} | {:error, any()}

  @doc """
  Get DNS challenge information for the order.

  ## Parameters
  - `app_name`: identifier of the requesting application, used for logging
  and correlation.
  - `order`: The ACME order
  - `account_key`: The ACME account key

  ## Returns
  - `{:ok, challenges}`: List of DNS challenges with record name and value
  - `{:error, reason}`: Failed to get challenges
  """
  @callback get_dns_challenges(
              app_name :: String.t(),
              order :: order(),
              account_key :: account_key()
            ) ::
              {:ok,
               [%{record_name: String.t(), record_value: String.t(), challenge: challenge()}]}
              | {:error, any()}

  @doc """
  Start validation for DNS challenges.

  ## Parameters
  - `app_name`: identifier of the requesting application, used for logging
  and correlation.
  - `challenges`: List of challenges to validate
  - `account_key`: The ACME account key

  ## Returns
  - `:ok`: Successfully started validation
  - `{:error, reason}`: Failed to start validation
  """
  @callback start_challenge_validation(
              app_name :: String.t(),
              challenges :: [challenge()],
              account_key :: account_key()
            ) :: :ok | {:error, any()}

  @doc """
  Wait for challenge validation to complete.

  ## Parameters
  - `app_name`: identifier of the requesting application, used for logging
  and correlation.
  - `challenges`: List of challenges to wait for
  - `account_key`: The ACME account key
  - `timeout_ms`: Maximum time to wait in milliseconds

  ## Returns
  - `:ok`: All challenges validated successfully
  - `{:error, reason}`: Validation failed or timed out
  """
  @callback wait_for_validation(
              app_name :: String.t(),
              challenges :: [challenge()],
              account_key :: account_key(),
              timeout_ms :: non_neg_integer()
            ) :: :ok | {:error, any()}

  @doc """
  Finalize the order and download the certificate.

  ## Parameters
  - `app_name`: identifier of the requesting application, used for logging
  and correlation.
  - `order`: The validated ACME order
  - `account_key`: The ACME account key
  - `options`: Client-specific options (e.g., key size)

  ## Returns
  - `{:ok, cert_chain_pem, private_key_pem}`: Successfully generated certificate
  - `{:error, reason}`: Failed to finalize certificate
  """
  @callback finalize_certificate(
              app_name :: String.t(),
              order :: order(),
              account_key :: account_key(),
              options :: map()
            ) :: {:ok, certificate_chain(), private_key_pem()} | {:error, any()}
end
