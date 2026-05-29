defmodule Foundation.Network do
  @moduledoc """
  A simple wrapper for network commands.
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

  ## Returns

  A list of DNS records matching the query. Returns an empty list `[]`
  if no records are found or the domain does not exist.

  ## Examples

      iex> Foundation.Network.lookup('example.com', :in, :txt)
      [['v=spf1 include:_spf.example.com ~all']]

      iex> Foundation.Network.lookup('nonexistent.example.com', :in, :txt)
      []

  """
  @spec lookup(domain_charlist(), dns_class(), dns_type()) :: [dns_record()]
  def lookup(domain_charlist, class, type) do
    :inet_res.lookup(domain_charlist, class, type)
  end
end
