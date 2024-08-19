defmodule Deployex.Fixture.Monitoring do
  @moduledoc """
  This module will handle fixtures for monitoring app structures
  """

  def deployex(attrs \\ %{}) do
    deployex = %Deployex.Status{
      name: "deployex",
      version: "1.2.3",
      otp: :connected,
      tls: :supported,
      supervisor: true,
      status: :running,
      uptime: "short time",
      last_ghosted_version: "-/-"
    }

    Map.merge(deployex, attrs)
  end

  def application(attrs \\ %{}) do
    application = %Deployex.Status{
      name: "my-test-app",
      instance: 1,
      version: "4.5.6",
      otp: :connected,
      tls: :supported,
      last_deployment: "full_deployment",
      supervisor: false,
      status: :running,
      restarts: 0,
      uptime: "long time"
    }

    Map.merge(application, attrs)
  end

  def list do
    [deployex(), application()]
  end
end
