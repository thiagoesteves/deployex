defmodule Foundation.Certificates.Importer.Route53 do
  @moduledoc """
  AWS Route53 implementation for exporting the certificate.
  """

  @behaviour Foundation.Certificates.Importer

  alias Foundation.Certificates.Importer

  require Logger

  @impl Importer
  def export_certificate(
        app_name,
        certificate_pem,
        chain_certificate_pem,
        private_key_pem,
        options
      ) do
    certificate_arn = options[:certificate_arn]
    certificate_blob = Base.encode64(certificate_pem)
    certificate_chain_blob = Base.encode64(chain_certificate_pem)
    private_key_blob = Base.encode64(private_key_pem)

    case certificate_blob
         |> ExAws.ACM.import_certificate(private_key_blob,
           certificate_arn: certificate_arn,
           certificate_chain: certificate_chain_blob
         )
         |> ExAws.request() do
      {:ok, %{"CertificateArn" => arn}} ->
        Logger.info("Successfully imported certificate to ACM: #{arn} for #{app_name}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to import certificate for #{app_name} reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
