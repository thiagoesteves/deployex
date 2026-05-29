defmodule Foundation.Catalog.Certificate do
  @moduledoc """
  Structure to handle the application certificate
  """

  @type t() :: %__MODULE__{
          domains: [String.t()] | nil,
          certificate_pem: String.t() | nil,
          chain_certificate_pem: String.t() | nil,
          private_key_pem: String.t() | nil,
          issuer: String.t() | nil,
          valid_from: DateTime.t() | nil,
          valid_until: DateTime.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  defstruct [
    :domains,
    :certificate_pem,
    :chain_certificate_pem,
    :private_key_pem,
    :issuer,
    :valid_from,
    :valid_until,
    :inserted_at,
    :updated_at
  ]

  alias X509.Certificate, as: X509Cert
  alias X509.RDNSequence

  @spec new(attrs :: map()) :: __MODULE__.t()
  def new(attrs) do
    struct(%__MODULE__{inserted_at: DateTime.utc_now()}, Map.from_struct(attrs))
  end

  @spec valid?(certificate :: __MODULE__.t(), non_neg_integer()) :: boolean()
  def valid?(
        %__MODULE__{
          valid_from: %DateTime{} = valid_from,
          valid_until: %DateTime{} = valid_until
        },
        threshold_days
      ) do
    now = DateTime.utc_now()

    renewal_threshold = DateTime.add(now, threshold_days * 24 * 60 * 60, :second)

    DateTime.compare(now, valid_from) in [:gt, :eq] and
      DateTime.after?(valid_until, now) and
      DateTime.after?(valid_until, renewal_threshold)
  end

  def valid?(_certificate, _threshold_days), do: false

  @doc """
  Extracts metadata from a certificate PEM string.

  Returns a map with the certificate metadata including issuer, validity dates, and SANs.

  ## Examples

      iex> metadata_from_cert_pem(cert_pem, "example.com")
      {:ok, %{issuer: "CN=...", valid_from: ~U[...], valid_until: ~U[...], sans: %{}}}

      iex> metadata_from_cert_pem(invalid_pem, "example.com")
      {:error, :invalid_certificate}
  """
  @spec metadata_from_cert_pem(String.t()) ::
          {:ok, %{issuer: String.t(), valid_from: DateTime.t(), valid_until: DateTime.t()}}
          | {:error, :invalid_certificate}
  def metadata_from_cert_pem(cert_pem) do
    case X509Cert.from_pem(cert_pem) do
      {:ok, x509_cert} ->
        {:Validity, {_, not_before}, {_, not_after}} = X509Cert.validity(x509_cert)

        valid_from = parse_x509_date(not_before)
        valid_until = parse_x509_date(not_after)

        issuer = x509_cert |> X509Cert.issuer() |> RDNSequence.to_string()

        {:ok,
         %{
           issuer: issuer,
           valid_from: valid_from,
           valid_until: valid_until
         }}

      {:error, _reason} ->
        {:error, :invalid_certificate}
    end
  end

  @spec split_certificate_chain(certificate_pem :: String.t()) ::
          {cert :: String.t(), cert_chain :: String.t()}
  def split_certificate_chain(certificate_pem) do
    # Split PEM into individual certificates
    certs = split_certificates(certificate_pem)

    case certs do
      [leaf] -> {leaf, ""}
      [leaf | chain] -> {leaf, Enum.join(chain, "")}
    end
  end

  defp split_certificates(certificate_pem) do
    certificate_pem
    |> String.split("-----END CERTIFICATE-----")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&(&1 <> "\n-----END CERTIFICATE-----\n"))
  end

  defp parse_x509_date(chars) when is_list(chars) do
    <<yy::binary-size(2), mm::binary-size(2), dd::binary-size(2), hh::binary-size(2),
      mi::binary-size(2), ss::binary-size(2), "Z">> =
      List.to_string(chars)

    yy_int = String.to_integer(yy)
    year = if yy_int < 50, do: 2000 + yy_int, else: 1900 + yy_int

    iso_8601 = "#{year}-#{mm}-#{dd}T#{hh}:#{mi}:#{ss}Z"
    {:ok, datetime, 0} = DateTime.from_iso8601(iso_8601)
    datetime
  end
end
