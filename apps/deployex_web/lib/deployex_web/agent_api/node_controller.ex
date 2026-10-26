defmodule DeployexWeb.AgentApi.NodeController do
  use DeployexWeb, :controller

  alias Deployer.Status

  action_fallback DeployexWeb.AgentApi.FallbackController

  def show(conn, _params) do
    with {:ok, deployex} <- deployex() do
      json(conn, %{
        node: deployex.node,
        version: deployex.version,
        started_at: deployex.started_at,
        otp_version: deployex.otp_version,
        elixir_version: deployex.elixir_version,
        host: host(Host.Info.latest())
      })
    end
  end

  defp deployex do
    with {:ok, monitoring} <- Status.monitoring(),
         %Status{} = deployex <- Enum.find(monitoring, &(&1.name == "deployex")) do
      {:ok, deployex}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp host(nil), do: nil

  defp host(%Host.Info{} = info) do
    %{
      os: info.host,
      description: info.description,
      uptime_seconds: info.uptime_seconds,
      cpus: info.cpus,
      cpu_percent: cpu_percent(info),
      memory_total: info.memory_total,
      memory_free: info.memory_free
    }
  end

  # Host.Info sums the cpu of every process, so a host with 2 cores can read up to 200
  defp cpu_percent(%Host.Info{cpu: cpu, cpus: cpus})
       when is_number(cpu) and is_integer(cpus) and cpus > 0,
       do: Float.round(cpu / cpus, 1)

  defp cpu_percent(_info), do: nil
end
