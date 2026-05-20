defmodule Foundation.Certificates.DNSProvider.Route53 do
  @moduledoc """
  AWS Route53 implementation for setting the DNS.
  """

  @behaviour Foundation.Certificates.DNSProvider

  alias Foundation.Certificates.DNSProvider

  require Logger

  @dialyzer {:nowarn_function, upsert_txt_record: 3}

  @impl DNSProvider
  def upsert_txt_record(name, txt_value, options) do
    txt_record_value = "\"#{txt_value}\""
    ttl = options[:ttl]
    zone = options[:zone]

    request =
      ExAws.Route53.change_record_sets(
        zone,
        comment: "ACME DNS-01 Challenge",
        action: :upsert,
        name: name,
        type: "TXT",
        ttl: ttl,
        records: [txt_record_value]
      )

    # NOTE: when using the AWS CLI or SDKs for Amazon Route 53, you must explicitly specify
    #       us-east-1 as the region for most operations in the standard AWS partition
    case ExAws.request(request, %{region: "us-east-1"}) do
      {:ok, _result} ->
        Logger.info("Successfully created/updated Route53 TXT record #{txt_value} for #{name}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to create Route53 TXT record: #{inspect(reason)}")
        {:error, {:route53_error, reason}}
    end
  end
end
