defmodule Foundation.Certificates.DNSProvider.Mock do
  @moduledoc """
  Mock implementation for setting the DNS.
  """

  @behaviour Foundation.Certificates.DNSProvider

  alias Foundation.Certificates.DNSProvider

  require Logger

  @impl DNSProvider
  def upsert_txt_record(name, txt_value, options) do
    ttl = options[:ttl]
    zone = options[:zone]

    Logger.info(
      "Mock DNS: Setting TXT record #{name} in zone #{zone} = #{txt_value} (TTL: #{ttl})"
    )

    :ok
  end
end
