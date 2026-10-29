# Adds the apps of the dev config that a running `make start` node does not manage yet, with the
# steps the YAML config watcher uses for an added app. `make dev-app` runs it after a publish.
[_name, host] = node() |> Atom.to_string() |> String.split("@")
target = :"deployex@#{host}"

if Node.connect(target) do
  # The config files call Mix, so the DeployEx node reads them
  config =
    :erpc.call(target, Config.Reader, :read!, [Path.expand("config/config.exs"), [env: :dev]])

  managed = :erpc.call(target, Foundation.Catalog, :applications, [])
  names = MapSet.new(managed, & &1.name)
  added = Enum.reject(config[:foundation][:applications], &MapSet.member?(names, &1.name))

  :ok = :erpc.call(target, Application, :put_env, [:foundation, :applications, managed ++ added])

  Enum.each(added, fn %{name: name} = app ->
    :erpc.call(target, Foundation.Catalog, :setup_new_app, [name])
    :erpc.call(target, Deployer.Monitor, :init_monitor_supervisor, [name])
    :erpc.call(target, Deployer.Engine, :init_worker, [app])

    :erpc.call(target, Foundation.Certificate, :start_certificate_manager, [
      name,
      Map.get(app, :certificates, [])
    ])

    IO.puts("DeployEx now manages #{name}.")
  end)
else
  IO.puts("DeployEx is not running. make start adds the published apps.")
end
