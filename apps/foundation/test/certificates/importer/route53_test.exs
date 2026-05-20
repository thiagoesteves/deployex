defmodule Foundation.Certificates.Importer.Route53Test do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Mock

  alias Foundation.Certificates.Importer.Route53

  @app_name "myapp"
  @certificate_pem "-----BEGIN CERTIFICATE-----\nMIIBcert\n-----END CERTIFICATE-----\n"
  @chain_pem "-----BEGIN CERTIFICATE-----\nMIIBchain\n-----END CERTIFICATE-----\n"
  @private_key_pem "-----BEGIN RSA PRIVATE KEY-----\nMIIBkey\n-----END RSA PRIVATE KEY-----\n"
  @certificate_arn "arn:aws:acm:us-east-1:123456789:certificate/abc-123"
  @options [certificate_arn: @certificate_arn]

  describe "export_certificate/5" do
    @tag :capture_log
    test "returns :ok and logs success when ACM import succeeds" do
      with_mocks([
        {ExAws.ACM, [],
         [
           import_certificate: fn _cert, _key, _opts -> %ExAws.Operation.JSON{} end
         ]},
        {ExAws, [],
         [
           request: fn _op -> {:ok, %{"CertificateArn" => @certificate_arn}} end
         ]}
      ]) do
        log =
          capture_log(fn ->
            assert :ok =
                     Route53.export_certificate(
                       @app_name,
                       @certificate_pem,
                       @chain_pem,
                       @private_key_pem,
                       @options
                     )
          end)

        assert log =~ "Successfully imported certificate to ACM"
        assert log =~ @certificate_arn
        assert log =~ @app_name
      end
    end

    @tag :capture_log
    test "returns {:error, reason} and logs error when ACM import fails" do
      reason = {:http_error, 400, "Invalid certificate"}

      with_mocks([
        {ExAws.ACM, [],
         [
           import_certificate: fn _cert, _key, _opts -> %ExAws.Operation.JSON{} end
         ]},
        {ExAws, [],
         [
           request: fn _op -> {:error, reason} end
         ]}
      ]) do
        log =
          capture_log(fn ->
            assert {:error, ^reason} =
                     Route53.export_certificate(
                       @app_name,
                       @certificate_pem,
                       @chain_pem,
                       @private_key_pem,
                       @options
                     )
          end)

        assert log =~ "Failed to import certificate"
        assert log =~ @app_name
      end
    end

    @tag :capture_log
    test "base64-encodes the certificate PEM before sending to ACM" do
      expected_cert_blob = Base.encode64(@certificate_pem)

      with_mocks([
        {ExAws.ACM, [],
         [
           import_certificate: fn cert_blob, _key, _opts ->
             assert cert_blob == expected_cert_blob
             %ExAws.Operation.JSON{}
           end
         ]},
        {ExAws, [],
         [
           request: fn _op -> {:ok, %{"CertificateArn" => @certificate_arn}} end
         ]}
      ]) do
        assert :ok =
                 Route53.export_certificate(
                   @app_name,
                   @certificate_pem,
                   @chain_pem,
                   @private_key_pem,
                   @options
                 )
      end
    end

    @tag :capture_log
    test "base64-encodes the private key PEM before sending to ACM" do
      expected_key_blob = Base.encode64(@private_key_pem)

      with_mocks([
        {ExAws.ACM, [],
         [
           import_certificate: fn _cert, key_blob, _opts ->
             assert key_blob == expected_key_blob
             %ExAws.Operation.JSON{}
           end
         ]},
        {ExAws, [],
         [
           request: fn _op -> {:ok, %{"CertificateArn" => @certificate_arn}} end
         ]}
      ]) do
        assert :ok =
                 Route53.export_certificate(
                   @app_name,
                   @certificate_pem,
                   @chain_pem,
                   @private_key_pem,
                   @options
                 )
      end
    end

    @tag :capture_log
    test "base64-encodes the chain PEM and passes it as certificate_chain option" do
      expected_chain_blob = Base.encode64(@chain_pem)

      with_mocks([
        {ExAws.ACM, [],
         [
           import_certificate: fn _cert, _key, opts ->
             assert opts[:certificate_chain] == expected_chain_blob
             %ExAws.Operation.JSON{}
           end
         ]},
        {ExAws, [],
         [
           request: fn _op -> {:ok, %{"CertificateArn" => @certificate_arn}} end
         ]}
      ]) do
        assert :ok =
                 Route53.export_certificate(
                   @app_name,
                   @certificate_pem,
                   @chain_pem,
                   @private_key_pem,
                   @options
                 )
      end
    end

    @tag :capture_log
    test "passes the certificate_arn from options to ACM" do
      with_mocks([
        {ExAws.ACM, [],
         [
           import_certificate: fn _cert, _key, opts ->
             assert opts[:certificate_arn] == @certificate_arn
             %ExAws.Operation.JSON{}
           end
         ]},
        {ExAws, [],
         [
           request: fn _op -> {:ok, %{"CertificateArn" => @certificate_arn}} end
         ]}
      ]) do
        assert :ok =
                 Route53.export_certificate(
                   @app_name,
                   @certificate_pem,
                   @chain_pem,
                   @private_key_pem,
                   @options
                 )
      end
    end

    @tag :capture_log
    test "returns error tuple preserving the original reason from ExAws" do
      reason = {:service_error, "EntityAlreadyExists", "Certificate already exists"}

      with_mocks([
        {ExAws.ACM, [],
         [
           import_certificate: fn _cert, _key, _opts -> %ExAws.Operation.JSON{} end
         ]},
        {ExAws, [],
         [
           request: fn _op -> {:error, reason} end
         ]}
      ]) do
        assert {:error, ^reason} =
                 Route53.export_certificate(
                   @app_name,
                   @certificate_pem,
                   @chain_pem,
                   @private_key_pem,
                   @options
                 )
      end
    end
  end
end
