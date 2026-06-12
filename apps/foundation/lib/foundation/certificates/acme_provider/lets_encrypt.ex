defmodule Foundation.Certificates.ACMEProvider.LetsEncrypt do
  @moduledoc """
  ExAcme client implementation for ACME certificate generation.

  This is the current implementation using the ExAcme library.
  It handles Let's Encrypt ACME v2 protocol with DNS-01 challenges.
  """

  @behaviour Foundation.Certificates.ACMEProvider

  alias Foundation.Certificates.ACMEProvider

  require Logger

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @impl ACMEProvider
  def setup_account(app_name, options) do
    name = server_name(app_name)
    key_path = app_key_path(app_name)
    url = options[:url]
    contact_email = options[:contact_email]

    with {:ok, _pid} <- start_acme_client(name, name, url),
         {:ok, account_key} <- load_or_create_account_key(app_name, key_path),
         {:ok, registration} <- build_registration(contact_email),
         {:ok, _account, account_key_with_kid} <-
           ExAcme.register_account(registration, account_key, name) do
      {:ok, account_key_with_kid}
    end
  end

  @impl ACMEProvider
  def create_order(app_name, domains, account_key) do
    name = server_name(app_name)

    order_request =
      Enum.reduce(domains, ExAcme.OrderBuilder.new_order(), fn domain, order ->
        ExAcme.OrderBuilder.add_dns_identifier(order, domain)
      end)

    ExAcme.submit_order(order_request, account_key, name)
  end

  @impl ACMEProvider
  def get_dns_challenges(app_name, order, account_key) do
    name = server_name(app_name)

    case order.authorizations do
      [] ->
        {:error, :no_authorizations}

      auth_urls ->
        challenges =
          Enum.map(auth_urls, fn auth_url ->
            with {:ok, authorization} <-
                   ExAcme.fetch_authorization(auth_url, account_key, name),
                 {:ok, challenge} <- find_dns_challenge(authorization),
                 {:ok, dns_challenge} <- calculate_dns_challenge(challenge, account_key),
                 {:ok, record_name} <- build_challenge_record_name(authorization) do
              %{
                record_name: record_name,
                record_value: dns_challenge,
                challenge: challenge
              }
            end
          end)

        case Enum.find(challenges, &match?({:error, _}, &1)) do
          nil -> {:ok, challenges}
          error -> error
        end
    end
  end

  @impl ACMEProvider
  def start_challenge_validation(app_name, challenges, account_key) do
    name = server_name(app_name)

    results =
      Enum.map(challenges, fn challenge_info ->
        actual_challenge = challenge_info.challenge

        ExAcme.start_challenge_validation(actual_challenge, account_key, name)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      {:error, reason} -> {:error, {:challenge_validation_failed, reason}}
    end
  end

  @impl ACMEProvider
  def wait_for_validation(app_name, challenges, account_key, options) do
    name = server_name(app_name)
    timeout_ms = options[:propagation_timeout_ms]
    poll_interval = options[:check_interval_ms]
    max_attempts = div(timeout_ms, poll_interval)

    wait_for_challenges_completion(app_name, name, challenges, account_key, max_attempts)
  end

  @impl ACMEProvider
  def finalize_certificate(app_name, order, account_key, options) do
    name = server_name(app_name)
    key_size = options[:key_size]
    order_attempts = options[:order_attempts] || 30
    private_key = X509.PrivateKey.new_rsa(key_size)
    {:ok, csr} = ExAcme.Order.to_csr(order, private_key)

    with {:ok, finalized_order} <-
           ExAcme.finalize_order(order, csr, account_key, name),
         :ok <- wait_until_order_valid(name, finalized_order, account_key, order_attempts),
         {:ok, cert_url} <- get_certificate_url(name, finalized_order, account_key),
         {:ok, cert_chain_pem} <- fetch_certificate_chain(name, cert_url, account_key) do
      {:ok, cert_chain_pem, X509.PrivateKey.to_pem(private_key)}
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp start_acme_client(app_name, name, dir_url) do
    case Process.whereis(name) do
      nil ->
        Logger.info("Connecting to ACME server: #{dir_url} for #{app_name}")
        ExAcme.start_link(name: name, directory_url: dir_url)

      _pid ->
        {:ok, :already_started}
    end
  end

  # sobelow_skip ["Traversal"]
  defp load_or_create_account_key(app_name, key_path) do
    case File.read(key_path) do
      {:ok, jwk_json} ->
        case JSON.decode(jwk_json) do
          {:ok, jwk_map} ->
            jwk = JOSE.JWK.from_map(jwk_map)
            {:ok, jwk}

          {:error, _reason} ->
            create_new_account_key(app_name, key_path)
        end

      {:error, _reason} ->
        create_new_account_key(app_name, key_path)
    end
  end

  defp create_new_account_key(app_name, key_path) do
    Logger.info("Generating new ACME account key for #{app_name}")
    jwk = ExAcme.generate_key()
    save_account_key(jwk, key_path)
    {:ok, jwk}
  end

  # sobelow_skip ["Traversal"]
  defp save_account_key(jwk, account_key_path) do
    {_metadata, jwk_map} = JOSE.JWK.to_map(jwk)
    jwk_json = JSON.encode!(jwk_map)

    File.mkdir_p!(Path.dirname(account_key_path))
    File.write!(account_key_path, jwk_json)
    :ok
  end

  defp build_registration(contact_email) do
    registration =
      ExAcme.RegistrationBuilder.new_registration()
      |> ExAcme.RegistrationBuilder.contacts(["mailto:" <> contact_email])
      |> ExAcme.RegistrationBuilder.agree_to_terms()

    {:ok, registration}
  end

  defp find_dns_challenge(authorization) do
    case ExAcme.Challenge.find_by_type(authorization, "dns-01") do
      nil -> {:error, :dns_challenge_not_found}
      challenge -> {:ok, challenge}
    end
  end

  defp calculate_dns_challenge(challenge, account_key) do
    key_authorization = ExAcme.Challenge.key_authorization(challenge.token, account_key)

    dns_challenge =
      :sha256
      |> :crypto.hash(key_authorization)
      |> Base.url_encode64(padding: false)

    {:ok, dns_challenge}
  rescue
    error -> {:error, {:dns_challenge_calculation_failed, error}}
  end

  defp build_challenge_record_name(authorization) do
    case authorization.identifier do
      %{"value" => domain} when is_binary(domain) ->
        record_name = "_acme-challenge." <> domain <> "."
        {:ok, record_name}

      _ ->
        {:error, :invalid_authorization}
    end
  end

  defp wait_for_challenges_completion(app_name, name, challenges, account_key, attempts)
       when attempts > 0 do
    all_valid =
      Enum.all?(challenges, fn challenge_info ->
        actual_challenge = challenge_info.challenge

        case ExAcme.fetch_challenge(actual_challenge.url, account_key, name) do
          {:ok, %{status: "valid"}} ->
            true

          {:ok, %{status: "pending"}} ->
            false

          {:error, reason} ->
            Logger.error("Challenge failed for #{app_name} reason: #{inspect(reason)}")
            false
        end
      end)

    if all_valid do
      :ok
    else
      Process.sleep(2_000)
      wait_for_challenges_completion(app_name, name, challenges, account_key, attempts - 1)
    end
  end

  defp wait_for_challenges_completion(_app_name, _name, _challenges, _account_key, 0) do
    {:error, :challenge_timeout}
  end

  defp wait_until_order_valid(name, order, account_key, attempts) when attempts > 0 do
    case ExAcme.fetch_order(order.url, account_key, name) do
      {:ok, %{status: "valid"}} ->
        :ok

      {:ok, %{status: status}} when status in ["pending", "processing"] ->
        Process.sleep(2_000)
        wait_until_order_valid(name, order, account_key, attempts - 1)

      {:ok, %{status: other}} ->
        {:error, {:order_failed, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_until_order_valid(_name, _order, _account_key, 0) do
    {:error, :order_timeout}
  end

  defp get_certificate_url(name, %ExAcme.Order{url: url}, account_key) do
    fetch_with_retry(name, url, account_key, 2)
  end

  defp fetch_with_retry(_name, _url, _account_key, 0) do
    {:error, :certificate_url_missing}
  end

  defp fetch_with_retry(name, url, account_key, attempts_left) do
    case ExAcme.fetch_order(url, account_key, name) do
      {:ok, %{certificate_url: cert_url}} when not is_nil(cert_url) ->
        {:ok, cert_url}

      {:retry_after, seconds} when seconds >= 0 ->
        milliseconds = seconds * 1_000
        Logger.warning("Acme fetching order for #{name} requested retry after #(seconds) s")
        Process.sleep(milliseconds)
        fetch_with_retry(name, url, account_key, attempts_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_certificate_chain(name, cert_url, account_key) do
    case ExAcme.fetch_certificates(cert_url, account_key, name) do
      {:ok, certificates} ->
        cert_chain_pem = Enum.map_join(certificates, "", &X509.Certificate.to_pem/1)
        {:ok, cert_chain_pem}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp server_name(name), do: String.to_atom("acme-" <> "#{name}")
  defp app_key_path(name), do: "/tmp/ex_acme_#{name}_account.jwk"
end
