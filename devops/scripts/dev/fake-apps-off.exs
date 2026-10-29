# Removes the fake apps of fake-apps.exs from a running `make start`. `make dev-fake-apps-off` evaluates it
# on the DeployEx node.
Application.put_env(:deployer, Deployer.Status, adapter: Deployer.Status.Application)
if pid = Process.whereis(DevFakeApps.Relay), do: GenServer.stop(pid)

for module <- [DevFakeApps.Relay, DevFakeApps.Status, DevFakeApps.Fakes] do
  :code.purge(module)
  :code.delete(module)
end

"DeployEx shows only its real apps again. Reload the dashboard."
