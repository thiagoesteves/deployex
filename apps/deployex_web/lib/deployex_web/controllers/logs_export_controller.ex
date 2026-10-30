defmodule DeployexWeb.LogsExportController do
  @moduledoc """
  Downloads the log lines that the Logs page or a dock logs tab selects, in full, as `.log` or `.jsonl`.
  The file is sent in chunks, one minute of lines each.
  """
  use DeployexWeb, :controller

  alias DeployexWeb.LogsExport

  def export(conn, params) do
    format = if params["format"] == "jsonl", do: "jsonl", else: "log"
    {:ok, host} = :inet.gethostname()

    conn =
      conn
      |> content_type(format)
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{LogsExport.filename(to_string(host), format)}")
      )
      |> send_chunked(200)

    # A closed connection, like a cancelled download, stops the reads
    Enum.reduce_while(LogsExport.chunks(params), conn, fn lines, conn ->
      case chunk(conn, LogsExport.render(lines, format)) do
        {:ok, conn} -> {:cont, conn}
        {:error, _closed} -> {:halt, conn}
      end
    end)
  end

  defp content_type(conn, "jsonl"), do: put_resp_content_type(conn, "application/x-ndjson")
  defp content_type(conn, _log), do: put_resp_content_type(conn, "text/plain")
end
