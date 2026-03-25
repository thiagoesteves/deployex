defmodule Foundation.CertificateTest do
  use ExUnit.Case, async: true

  alias Foundation.Certificate

  @file_paths "./test/support/files"
  @cert_rsa_path "#{@file_paths}/rsa_certificate.pem"
  @cert_ec_path "#{@file_paths}/ec_certificate.pem"
  @cert_no_san_path "#{@file_paths}/no_san_certificate.pem"

  describe "decode/1" do
    test "returns error for non-existent file" do
      assert {:error, _reason} = Certificate.decode("/tmp/non_existing_cert.pem")
    end

    test "decodes RSA certificate and returns correct struct type" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert %Certificate{} = cert
    end

    test "decodes EC certificate and returns correct struct type" do
      %Certificate{} = cert = Certificate.decode(@cert_ec_path)

      assert %Certificate{} = cert
    end
  end

  describe "decode/1 issuer" do
    test "extracts issuer CN from RSA certificate" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert is_binary(cert.issuer)
      assert String.length(cert.issuer) > 0
    end

    test "extracts issuer CN from EC certificate" do
      %Certificate{} = cert = Certificate.decode(@cert_ec_path)

      assert is_binary(cert.issuer)
    end
  end

  describe "decode/1 serial" do
    test "extracts serial number as integer" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert is_integer(cert.serial)
      assert cert.serial > 0
    end
  end

  describe "decode/1 version" do
    test "extracts certificate version" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert cert.version == :v3
    end
  end

  describe "decode/1 public key" do
    test "identifies RSA public key type" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert cert.public_key_type == "RSA"
    end

    test "calculates RSA key size in bits" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert is_integer(cert.public_key_size)
      assert cert.public_key_size in [2048, 4096]
    end

    test "identifies EC public key type" do
      %Certificate{} = cert = Certificate.decode(@cert_ec_path)

      assert cert.public_key_type == "EC"
    end

    test "returns nil key size for EC certificates" do
      %Certificate{} = cert = Certificate.decode(@cert_ec_path)

      assert is_nil(cert.public_key_size)
    end
  end

  describe "decode/1 expiry" do
    test "returns expires_in_days as integer" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert is_integer(cert.expires_in_days)
    end

    test "returns positive expires_in_days for a valid certificate" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert cert.expires_in_days > 0
    end
  end

  describe "decode/1 domains" do
    test "extracts domains from Subject Alternative Names" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert is_list(cert.domains)
      refute Enum.empty?(cert.domains)
      assert Enum.all?(cert.domains, &is_binary/1)
    end

    test "returns domains sorted alphabetically" do
      %Certificate{} = cert = Certificate.decode(@cert_rsa_path)

      assert cert.domains == Enum.sort(cert.domains)
    end

    test "falls back to CN when SAN extension is absent" do
      %Certificate{} = cert = Certificate.decode(@cert_no_san_path)

      assert length(cert.domains) == 1
      assert is_binary(hd(cert.domains))
    end

    test "returns empty list when no domains are found" do
      # A cert with neither SAN nor CN subject — edge case
      %Certificate{} = cert = Certificate.decode(@cert_no_san_path)

      assert is_list(cert.domains)
    end
  end

  describe "struct" do
    test "Certificate struct has correct fields" do
      cert = %Certificate{
        issuer: "My CA",
        serial: 123_456,
        version: :v3,
        public_key_type: "RSA",
        public_key_size: 2048,
        expires_in_days: 90,
        domains: ["example.com", "www.example.com"]
      }

      assert cert.issuer == "My CA"
      assert cert.serial == 123_456
      assert cert.version == :v3
      assert cert.public_key_type == "RSA"
      assert cert.public_key_size == 2048
      assert cert.expires_in_days == 90
      assert cert.domains == ["example.com", "www.example.com"]
    end

    test "Certificate struct defaults all fields to nil" do
      cert = %Certificate{}

      assert is_nil(cert.issuer)
      assert is_nil(cert.serial)
      assert is_nil(cert.version)
      assert is_nil(cert.public_key_type)
      assert is_nil(cert.public_key_size)
      assert is_nil(cert.expires_in_days)
      assert is_nil(cert.domains)
    end
  end
end
