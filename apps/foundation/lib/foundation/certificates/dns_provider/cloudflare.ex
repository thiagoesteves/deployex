defmodule Foundation.Certificates.DNSProvider.Cloudflare do
  @moduledoc """
  Cloudflare implementation for setting DNS TXT records for ACME DNS-01 challenges.

  Required options:
  - `:api_token` - Cloudflare API token with DNS edit permissions
  - `:zone_id`   - Cloudflare Zone ID for the domain
  - `:ttl`       - TTL in seconds (minimum 60; use 1 for "auto")
  """

  @behaviour Foundation.Certificates.DNSProvider

  alias Foundation.Certificates.DNSProvider

  require Logger

  @base_url "https://api.cloudflare.com/client/v4"

  @impl DNSProvider
  def upsert_txt_record(name, txt_value, options) do
    api_token = options[:api_token]
    zone = options[:zone]
    ttl = options[:ttl]

    headers = [
      {"authorization", "Bearer #{api_token}"},
      {"content-type", "application/json"}
    ]

    # Format data to cloudflare
    record_name = String.trim_trailing(name, ".")
    txt_value = "\"#{txt_value}\""

    # NOTE: https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/list
    query =
      URI.encode_query(%{
        match: "all",
        type: "TXT",
        name: record_name
      })

    search_url = "#{@base_url}/zones/#{zone}/dns_records?#{query}"

    case Req.get(search_url, headers: headers, params: []) do
      {:ok, %{status: status, body: %{"result" => []}}}
      when status in [200, 201] ->
        create_record(zone, record_name, txt_value, ttl, headers)

      {:ok, %{status: status, body: %{"result" => [%{"id" => id} | _]}}}
      when status in [200, 201] ->
        update_record(zone, id, record_name, txt_value, ttl, headers)

      {_, reason} ->
        Logger.error("Failed to search Cloudflare TXT records for #{name}: #{inspect(reason)}")
        {:error, {:cloudflare_error, reason}}
    end
  end

  # NOTE: https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/create/
  defp create_record(zone, name, content, ttl, headers) do
    url = "#{@base_url}/zones/#{zone}/dns_records"

    body = %{
      type: "TXT",
      name: name,
      content: content,
      ttl: ttl,
      comment: "ACME DNS-01 Challenge"
    }

    case Req.post(url, headers: headers, json: body) do
      {:ok, %{status: status}} when status in [200, 201] ->
        Logger.info("Successfully created Cloudflare TXT record #{content} for #{name}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to create Cloudflare TXT record #{name}: #{inspect(reason)}")
        {:error, {:cloudflare_error, reason}}
    end
  end

  # NOTE: https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/update
  defp update_record(zone, record_id, name, content, ttl, headers) do
    url = "#{@base_url}/zones/#{zone}/dns_records/#{record_id}"

    body = %{
      type: "TXT",
      name: name,
      content: content,
      ttl: ttl,
      comment: "ACME DNS-01 Challenge"
    }

    case Req.put(url, headers: headers, json: body) do
      {:ok, %{status: 200}} ->
        Logger.info("Successfully updated Cloudflare TXT record #{name}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to update Cloudflare TXT record #{name}: #{inspect(reason)}")
        {:error, {:cloudflare_error, reason}}
    end
  end
end
