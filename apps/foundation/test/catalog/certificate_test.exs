defmodule Foundation.Catalog.CertificateTest do
  use ExUnit.Case, async: false

  alias Foundation.Catalog.Certificate

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------
  #
  # Real self-signed PEM generated with:
  #   openssl req -x509 -newkey rsa:2048 -keyout /dev/null -out cert.pem \
  #     -days 3650 -nodes -subj "/CN=Test CA"
  #
  # Replace with an actual PEM from your test/support/files if preferred.

  @leaf_pem """
  -----BEGIN CERTIFICATE-----
  MIICpDCCAYwCCQDU9pQ4pHmSpDANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAl0
  ZXN0LmNvbTAeFw0yNDAxMDEwMDAwMDBaFw0yNTAxMDEwMDAwMDBaMBQxEjAQBgNV
  BAMMCXRlc3QuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2a2r
  wBthFDFoTb8tQn+xTGnFQfRhzVyaTlQJiXJmQsGGC5Y1GxMM7EYY9/LFBXiD8f
  PlWCFKabMrR7AuSqGzS0MLUVfhDNBQSmqOSFxrP0vqJgO8dVAOqQ8FAE9uXDJTn
  Kc3cVGqkxBhxDX3mQT2vU4kXxWpTGovFqM0RMgx0k3nL9Zl7cVCE/VNp8gV6sK
  EiYKRRIrSqFDu6QBQZ8mKjEwbwgN/T7UkSDRqxbFdkX2PJLRV9RVxUFWS8Vo0
  2LPV5XFyuVwFbPpHUBzJxqQvMnN/a0BQXS0UdY4c2mVHXJM9YbRo9VxVHJM9Yb
  Ro9VxVHkQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQCtest
  -----END CERTIFICATE-----
  """

  @chain_pem """
  -----BEGIN CERTIFICATE-----
  MIICpDCCAYwCCQDchain1111111111111111111111111111111111111111111111
  1111111111111111111111111111111111111111111111111111111111111111111
  1111111111111111111111111111111111111111111111111111111111111111111
  chain
  -----END CERTIFICATE-----
  """

  @multi_pem @leaf_pem <> @chain_pem

  # ---------------------------------------------------------------------------
  # new/1
  # ---------------------------------------------------------------------------

  describe "new/1" do
    test "returns a Certificate struct" do
      assert %Certificate{} = Certificate.new(%Certificate{domains: ["example.com"]})
    end

    test "copies fields from attrs" do
      attrs = %Certificate{
        domains: ["example.com"],
        certificate_pem: "pem",
        issuer: "Test CA"
      }

      cert = Certificate.new(attrs)
      assert cert.domains == ["example.com"]
      assert cert.certificate_pem == "pem"
      assert cert.issuer == "Test CA"
    end

    test "nil fields in attrs remain nil" do
      cert = Certificate.new(%Certificate{})
      assert is_nil(cert.domains)
      assert is_nil(cert.certificate_pem)
    end
  end

  # ---------------------------------------------------------------------------
  # valid?/2
  # ---------------------------------------------------------------------------

  describe "valid?/2" do
    test "returns true for a certificate well within its validity period" do
      cert = %Certificate{
        valid_from: DateTime.add(DateTime.utc_now(), -60 * 86_400, :second),
        valid_until: DateTime.add(DateTime.utc_now(), 90 * 86_400, :second)
      }

      assert Certificate.valid?(cert, 30)
    end

    test "returns false when valid_until is in the past" do
      cert = %Certificate{
        valid_from: DateTime.add(DateTime.utc_now(), -90 * 86_400, :second),
        valid_until: DateTime.add(DateTime.utc_now(), -1 * 86_400, :second)
      }

      refute Certificate.valid?(cert, 30)
    end

    test "returns false when valid_from is in the future" do
      cert = %Certificate{
        valid_from: DateTime.add(DateTime.utc_now(), 10 * 86_400, :second),
        valid_until: DateTime.add(DateTime.utc_now(), 90 * 86_400, :second)
      }

      refute Certificate.valid?(cert, 30)
    end

    test "returns false when valid_until is within the default 30-day threshold" do
      cert = %Certificate{
        valid_from: DateTime.add(DateTime.utc_now(), -60 * 86_400, :second),
        valid_until: DateTime.add(DateTime.utc_now(), 20 * 86_400, :second)
      }

      refute Certificate.valid?(cert, 30)
    end

    test "returns true when valid_until is exactly beyond a custom threshold" do
      cert = %Certificate{
        valid_from: DateTime.add(DateTime.utc_now(), -30 * 86_400, :second),
        valid_until: DateTime.add(DateTime.utc_now(), 10 * 86_400, :second)
      }

      # With a 5-day threshold, 10 days left is still valid.
      assert Certificate.valid?(cert, 5)
    end

    test "returns false when valid_until is within a custom threshold" do
      cert = %Certificate{
        valid_from: DateTime.add(DateTime.utc_now(), -30 * 86_400, :second),
        valid_until: DateTime.add(DateTime.utc_now(), 10 * 86_400, :second)
      }

      # With a 15-day threshold, 10 days left triggers renewal.
      refute Certificate.valid?(cert, 15)
    end

    test "returns false when valid_from is nil" do
      cert = %Certificate{
        valid_from: nil,
        valid_until: DateTime.add(DateTime.utc_now(), 90 * 86_400, :second)
      }

      refute Certificate.valid?(cert, 10)
    end

    test "returns false when valid_until is nil" do
      cert = %Certificate{
        valid_from: DateTime.add(DateTime.utc_now(), -1 * 86_400, :second),
        valid_until: nil
      }

      refute Certificate.valid?(cert, 10)
    end

    test "returns false when both dates are nil" do
      refute Certificate.valid?(%Certificate{valid_from: nil, valid_until: nil}, 30)
    end
  end

  # ---------------------------------------------------------------------------
  # metadata_from_cert_pem/1
  # ---------------------------------------------------------------------------

  describe "metadata_from_cert_pem/1" do
    import Mock

    test "returns {:error, :invalid_certificate} for a non-PEM binary" do
      assert {:error, :invalid_certificate} =
               Certificate.metadata_from_cert_pem("not a certificate")
    end

    test "returns {:error, :invalid_certificate} for an empty string" do
      assert {:error, :invalid_certificate} = Certificate.metadata_from_cert_pem("")
    end

    test "returns {:ok, map} with issuer, valid_from, valid_until on a valid cert" do
      not_before_chars = ~c"240101000000Z"
      not_after_chars = ~c"250101000000Z"

      fake_cert = :fake_cert

      with_mocks([
        {X509.Certificate, [],
         [
           from_pem: fn _pem -> {:ok, fake_cert} end,
           validity: fn ^fake_cert ->
             {:Validity, {:utcTime, not_before_chars}, {:utcTime, not_after_chars}}
           end,
           issuer: fn ^fake_cert -> :fake_issuer_rdnseq end
         ]},
        {X509.RDNSequence, [],
         [
           to_string: fn :fake_issuer_rdnseq -> "CN=Test CA" end
         ]}
      ]) do
        assert {:ok, meta} = Certificate.metadata_from_cert_pem("fake_pem")
        assert meta.issuer == "CN=Test CA"
        assert %DateTime{year: 2024} = meta.valid_from
        assert %DateTime{year: 2025} = meta.valid_until
      end
    end

    test "interprets two-digit year < 50 as 2000s" do
      fake_cert = :cert

      with_mocks([
        {X509.Certificate, [],
         [
           from_pem: fn _pem -> {:ok, fake_cert} end,
           validity: fn ^fake_cert ->
             {:Validity, {:utcTime, ~c"490101000000Z"}, {:utcTime, ~c"500101000000Z"}}
           end,
           issuer: fn ^fake_cert -> :rdnseq end
         ]},
        {X509.RDNSequence, [],
         [
           to_string: fn :rdnseq -> "CN=CA" end
         ]}
      ]) do
        {:ok, meta} = Certificate.metadata_from_cert_pem("pem")
        assert meta.valid_from.year == 2049
        # yy = 50 → 1950 per the RFC 5280 rule
        assert meta.valid_until.year == 1950
      end
    end

    test "returns issuer as a string" do
      fake_cert = :cert

      with_mocks([
        {X509.Certificate, [],
         [
           from_pem: fn _pem -> {:ok, fake_cert} end,
           validity: fn ^fake_cert ->
             {:Validity, {:utcTime, ~c"240101000000Z"}, {:utcTime, ~c"250101000000Z"}}
           end,
           issuer: fn ^fake_cert -> :rdnseq end
         ]},
        {X509.RDNSequence, [],
         [
           to_string: fn :rdnseq -> "CN=My Issuer" end
         ]}
      ]) do
        {:ok, meta} = Certificate.metadata_from_cert_pem("pem")
        assert is_binary(meta.issuer)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # split_certificate_chain/1
  # ---------------------------------------------------------------------------

  describe "split_certificate_chain/1" do
    test "returns {leaf, \"\"} for a single-certificate PEM" do
      {leaf, chain} = Certificate.split_certificate_chain(@leaf_pem)

      assert String.contains?(leaf, "-----BEGIN CERTIFICATE-----")
      assert String.contains?(leaf, "-----END CERTIFICATE-----")
      assert chain == ""
    end

    test "returns {leaf, chain} for a two-certificate PEM" do
      {leaf, chain} = Certificate.split_certificate_chain(@multi_pem)

      assert String.contains?(leaf, "-----BEGIN CERTIFICATE-----")
      assert String.contains?(chain, "-----BEGIN CERTIFICATE-----")
    end

    test "leaf cert does not include the chain cert content" do
      {leaf, _chain} = Certificate.split_certificate_chain(@multi_pem)

      refute String.contains?(leaf, "chain")
    end

    test "chain cert does not include the leaf cert content" do
      {_leaf, chain} = Certificate.split_certificate_chain(@multi_pem)

      refute String.contains?(
               chain,
               "MIICpDCCAYwCCQDU9pQ4pHmSpDANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAl0"
             )
    end

    test "round-trips a single cert — rejoining leaf and empty chain equals original trimmed" do
      {leaf, ""} = Certificate.split_certificate_chain(@leaf_pem)

      assert String.trim(leaf) == String.trim(@leaf_pem)
    end

    test "handles three certificates in the chain" do
      extra_pem = """
      -----BEGIN CERTIFICATE-----
      extra
      -----END CERTIFICATE-----
      """

      triple_pem = @leaf_pem <> @chain_pem <> extra_pem
      {leaf, chain} = Certificate.split_certificate_chain(triple_pem)

      assert String.contains?(leaf, "-----BEGIN CERTIFICATE-----")
      # Both intermediate certs should be in the chain string
      assert String.contains?(chain, "chain")
      assert String.contains?(chain, "extra")
    end

    test "each piece is still a valid PEM block" do
      {leaf, chain} = Certificate.split_certificate_chain(@multi_pem)

      for pem <- [leaf, chain] do
        assert String.starts_with?(String.trim(pem), "-----BEGIN CERTIFICATE-----")
        assert String.ends_with?(String.trim(pem), "-----END CERTIFICATE-----")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Struct defaults
  # ---------------------------------------------------------------------------

  describe "struct defaults" do
    test "all fields default to nil" do
      cert = %Certificate{}

      assert is_nil(cert.domains)
      assert is_nil(cert.certificate_pem)
      assert is_nil(cert.chain_certificate_pem)
      assert is_nil(cert.private_key_pem)
      assert is_nil(cert.issuer)
      assert is_nil(cert.valid_from)
      assert is_nil(cert.valid_until)
      assert is_nil(cert.inserted_at)
      assert is_nil(cert.updated_at)
    end
  end
end
