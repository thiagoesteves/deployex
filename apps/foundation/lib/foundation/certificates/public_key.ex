defmodule Foundation.Certificates.PublicKey do
  @moduledoc """
  Extracts and structures public key certificate metadata from X.509 certificates.
  """

  require Logger

  @type t() :: %__MODULE__{
          issuer: String.t() | nil,
          serial: String.t() | nil,
          version: String.t() | nil,
          public_key_type: [String.t()] | nil,
          public_key_size: integer() | nil,
          expires_in_days: integer() | nil,
          domains: list()
        }

  defstruct [
    :issuer,
    :serial,
    :version,
    :public_key_type,
    :public_key_size,
    :expires_in_days,
    :domains
  ]

  @doc """
  Reads a PEM-encoded certificate from the given file path and returns a
  `%PublicKey{}` struct with the extracted metadata.

  Returns `{:error, reason}` if the file cannot be read or the certificate
  cannot be parsed.

  ## Examples

      iex> PublicKey.decode("/path/to/cert.pem")
      %PublicKey{issuer: "My CA", expires_in_days: 365, ...}

      iex> PublicKey.decode("/nonexistent.pem")
      {:error, :enoent}
  """
  @spec decode(certificate_path :: String.t()) :: t() | {:error, term()}
  def decode(certificate_path) do
    with {:ok, certificate_pem} <- File.read(certificate_path) do
      decode_pem(certificate_pem)
    end
  end

  @doc """
  Parses a PEM-encoded certificate string and returns a `%PublicKey{}` struct
  with the extracted metadata.

  ## Examples

      iex> PublicKey.decode_pem(pem_string)
      %PublicKey{issuer: "My CA", public_key_type: "RSA", public_key_size: 2048, ...}

      iex> PublicKey.decode_pem(nil)
      {:error, :not_found}
  """
  @spec decode_pem(certificate_pem :: String.t() | nil) :: t() | {:error, term()}
  def decode_pem(nil), do: {:error, :not_found}

  def decode_pem(certificate_pem) do
    case X509.Certificate.from_pem(certificate_pem) do
      {:ok, parsed} ->
        pubkey = X509.Certificate.public_key(parsed)

        %__MODULE__{
          issuer: extract_issuer(parsed),
          serial: X509.Certificate.serial(parsed),
          version: X509.Certificate.version(parsed),
          public_key_type: key_type(pubkey),
          public_key_size: key_size(pubkey),
          expires_in_days: parsed |> extract_expiry() |> expires_in(),
          domains: extract_domains(parsed)
        }

      {:error, reason} = error ->
        Logger.error(
          "Error while reading certificate: #{certificate_pem}, reason: #{inspect(reason)}"
        )

        error
    end
  end

  # Extracts the issuer CN from the certificate
  defp extract_issuer(certificate) do
    with {:rdnSequence, rdn_seq} <- X509.Certificate.issuer(certificate) do
      rdn_seq
      |> List.flatten()
      |> Enum.find_value(fn
        {:AttributeTypeAndValue, {2, 5, 4, 10}, {:printableString, cn}} -> to_string(cn)
        {:AttributeTypeAndValue, {2, 5, 4, 3}, {:utf8String, cn}} -> to_string(cn)
        {:AttributeTypeAndValue, {2, 5, 4, 3}, cn} when is_list(cn) -> to_string(cn)
        _ -> nil
      end)
    end
  end

  # Extracts the expiry date from the certificate validity
  defp extract_expiry(certificate) do
    certificate
    |> X509.Certificate.validity()
    |> case do
      {:Validity, _not_before, not_after} -> to_date(not_after)
      _ -> nil
    end
  end

  # Converts ASN.1 time formats to Elixir Date
  defp to_date({:utcTime, time}) do
    # Format: YYMMDDHHMMSSZ
    <<y1, y2, mo1, mo2, d1, d2, _rest::binary>> = to_string(time)
    year = String.to_integer("20#{<<y1, y2>>}")
    month = String.to_integer(<<mo1, mo2>>)
    day = String.to_integer(<<d1, d2>>)
    Date.new!(year, month, day)
  end

  defp to_date({:generalTime, time}) do
    # Format: YYYYMMDDHHMMSSZ
    <<y1, y2, y3, y4, mo1, mo2, d1, d2, _rest::binary>> = to_string(time)
    year = String.to_integer(<<y1, y2, y3, y4>>)
    month = String.to_integer(<<mo1, mo2>>)
    day = String.to_integer(<<d1, d2>>)
    Date.new!(year, month, day)
  end

  defp to_date(_), do: nil

  # Extracts domain names from Subject Alternative Names (SAN) extension,
  # falling back to Common Name if SAN is not present
  defp extract_domains(certificate) do
    extract_by_extension(certificate) || extract_by_subject(certificate) || []
  end

  defp extract_by_extension(certificate) do
    with {:Extension, _, _, san_values} <-
           X509.Certificate.extension(certificate, :subject_alt_name) do
      san_values
      |> Enum.map(fn
        {:dNSName, domain} -> to_string(domain)
        _ -> nil
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.sort()
    end
  end

  defp extract_by_subject(certificate) do
    with {:rdnSequence, rdn_seq} <- X509.Certificate.subject(certificate) do
      rdn_seq
      |> List.flatten()
      |> Enum.find_value(fn
        {:AttributeTypeAndValue, {2, 5, 4, 3}, {:utf8String, cn}} -> to_string(cn)
        _ -> nil
      end)
      |> case do
        nil -> []
        cn -> [cn]
      end
    end
  end

  # Calculates days until expiration
  defp expires_in(nil), do: nil
  defp expires_in(date), do: Date.diff(date, Date.utc_today())

  # Determines the public key algorithm type
  defp key_type({:RSAPublicKey, _modulus, _exponent}), do: "RSA"
  defp key_type({{:ECPoint, _}, _}), do: "EC"
  defp key_type(_), do: "Unknown"

  # Calculates RSA key size in bits
  defp key_size({:RSAPublicKey, modulus, _exponent}),
    do: modulus |> Integer.to_string(2) |> String.length()

  defp key_size(_), do: nil
end
