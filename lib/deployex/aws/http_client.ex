defmodule Deployex.Aws.ExAwsHttpClient do
  @moduledoc """
  Http Cient beahviour implementation using Finch
  """
  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body, headers, _http_opts) do
    case Finch.build(method, url, headers, body)
         |> Finch.request(ExAws.Request.Finch) do
      {:ok, resp} ->
        {:ok, %{status_code: resp.status, body: resp.body, headers: resp.headers}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end
