defmodule Foundation.Network do
  @moduledoc """
  Provides network utility functions, including DNS resolution via Erlang's `:inet_res`.

  Supports querying DNS records (A, AAAA, MX, NS, CNAME, TXT, SOA, PTR, SRV) with
  optional nameserver configuration.
  """

  ### ==========================================================================
  ### Types
  ### ==========================================================================

  @type domain_charlist :: charlist()
  @type dns_class :: :in | :chaos | :hs | :any
  @type dns_type :: :a | :aaaa | :mx | :ns | :cname | :txt | :soa | :ptr | :srv
  @type dns_record :: [charlist()] | tuple()

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @doc """
  Performs a DNS lookup for the given domain and record type.

  Delegates to Erlang's `:inet_res.lookup/3` to query DNS records
  of the specified type for a domain.

  ## Parameters

    - `domain_charlist` - The domain name as a charlist (e.g. `'example.com'`)
    - `class` - The DNS class, typically `:in` (Internet)
    - `type` - The DNS record type (e.g. `:txt`, `:a`, `:mx`, `:cname`)

  ## Options

    - `:nameservers` - List of `{ip_tuple, port}` nameservers to query (e.g. `[{{8, 8, 8, 8}, 53}]`)
    - `:timeout` - Timeout in milliseconds for each query attempt (default: `2000`)
    - `:retry` - Number of retry attempts before giving up (default: `3`)
    - `:alt_nameservers` - Fallback nameservers used after `:nameservers` are exhausted

  ## Returns

  A list of DNS records matching the query. Returns an empty list `[]`
  if no records are found or the domain does not exist.

  ## Examples

      iex> Foundation.Network.lookup('example.com', :in, :txt, nameservers: [{{8, 8, 8, 8}, 53}]))
      [['v=spf1 include:_spf.example.com ~all']]

      iex> Foundation.Network.lookup('nonexistent.example.com', :in, :txt, nameservers: [{{8, 8, 8, 8}, 53}, {{1, 1, 1, 1}, 53}])
      []

  """
  @spec lookup(domain_charlist(), dns_class(), dns_type(), keyword()) :: [dns_record()]
  def lookup(domain_charlist, class, type, opts) do
    :inet_res.lookup(domain_charlist, class, type, opts)
  end
end
