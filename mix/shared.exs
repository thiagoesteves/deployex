defmodule Mix.Shared do
  def version, do: "0.4.2-rc1"

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
        Deployer.Monitor.Supervisor,
        Deployer.Release.Version,
        Deployer.Fixture.Binary,
        Foundation.Fixture.Catalog,
        # DeployEx Web
        DeployexWeb.Application,
        DeployexWeb.Layouts,
        DeployexWeb.PageHTML,
        DeployexWeb.Telemetry,
        DeployexWeb.ErrorHTML,
        DeployexWeb.CoreComponents,
        DeployexWeb.Fixture.Status,
        DeployexWeb.Fixture.Binary,
        DeployexWeb.Fixture.Monitoring,
        DeployexWeb.Fixture.Nodes,
        DeployexWeb.Fixture.Terminal,
        # Foundation
        Foundation.Rpc,
        Foundation.RpcMock,
        Foundation.Macros,
        Foundation.Application,
        # Host
        Host.Memory,
        Host.Commander.Local,
        Host.Terminal.Server.Message,
        Host.Application,
        # Sentinel
        Sentinel.Application
      ]
    ]
  end
end
