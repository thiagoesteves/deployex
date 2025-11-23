defmodule Mix.Shared do
  def version, do: "0.8.1-rc3"

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
        Deployer.Engine,
        Deployer.Engine.Supervisor,
        Deployer.Release.Version,
        Deployer.Monitor.Service,
        Deployer.Fixture.Files,
        # DeployEx Web
        DeployexWeb.Application,
        DeployexWeb.Layouts,
        DeployexWeb.PageHTML,
        DeployexWeb.Telemetry,
        DeployexWeb.ErrorHTML,
        DeployexWeb.CoreComponents,
        DeployexWeb.Fixture.Status,
        # Foundation
        Foundation.Rpc,
        Foundation.RpcMock,
        Foundation.Macros,
        Foundation.Application,
        Foundation.Catalog.Version,
        Foundation.Catalog.Node,
        # Host
        Host.Info,
        Host.Commander.Local,
        Host.Terminal.Server.Message,
        Host.Application,
        Host.Terminal.Supervisor,
        Host.Fixture.Terminal,
        # Sentinel
        Sentinel.Application,
        Sentinel.Watchdog.Data
      ]
    ]
  end
end
