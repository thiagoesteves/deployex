defmodule Mix.Shared do
  def version, do: "0.4.2"

  def elixir, do: "~> 1.16"

  def elixirc_paths do
    if Mix.env() == :test do
      ["lib", "test/support"]
    else
      ["lib"]
    end
  end

  def test_coverage do
    [
      summary: [threshold: 94],
      ignore_modules: [
        # Deployer
        Deployer.Application,
        Deployer.Monitor.Adapter,
        Deployer.Monitor.Supervisor,
        Deployer.Release.Version,
        Deployer.Fixture.Files,
        # DeployEx Web
        DeployexWeb.Application,
        DeployexWeb.Layouts,
        DeployexWeb.PageHTML,
        DeployexWeb.Telemetry,
        DeployexWeb.ErrorHTML,
        DeployexWeb.CoreComponents,
        DeployexWeb.Fixture.Status,
        DeployexWeb.Fixture.Terminal,
        # Foundation
        Foundation.Rpc,
        Foundation.RpcMock,
        Foundation.Macros,
        Foundation.Application,
        Foundation.Catalog.Version,
        Foundation.Catalog.Sname,
        # Host
        Host.Memory,
        Host.Commander.Local,
        Host.Terminal.Server.Message,
        Host.Application,
        Host.Terminal.Supervisor,
        # Sentinel
        Sentinel.Application,
        Sentinel.Watchdog.Data
      ]
    ]
  end
end
