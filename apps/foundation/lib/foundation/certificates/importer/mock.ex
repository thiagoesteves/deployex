defmodule Foundation.Certificates.Importer.Mock do
  @moduledoc """
  Mock implementation for exporting the certificate.
  """

  @behaviour Foundation.Certificates.Importer

  alias Foundation.Certificates.Importer

  require Logger

  @impl Importer
  def export_certificate(app_name, _certificate, _chain_certificate, _private_key, options) do
    certificate_arn = options[:certificate_arn]
    Logger.info("Mock DNS: Exporting certificate #{certificate_arn} for #{app_name}")
    :ok
  end
end
