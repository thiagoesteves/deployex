defmodule DeployexWeb.LogsExportController do
  @moduledoc """
  Downloads the log lines that the Logs page or a dock logs tab selects, in full, as `.log` or `.jsonl`.
  """
  use DeployexWeb, :controller

  alias DeployexWeb.LogsExport

  def export(conn, params) do
    format = if params["format"] == "jsonl", do: "jsonl", else: "log"
    {:ok, host} = :inet.gethostname()
    data = params |> LogsExport.lines() |> LogsExport.render(format) |> IO.iodata_to_binary()

    send_download(conn, {:binary, data},
      filename: LogsExport.filename(to_string(host), format),
      content_type: if(format == "jsonl", do: "application/x-ndjson", else: "text/plain"),
      charset: "utf-8"
    )
  end
end
