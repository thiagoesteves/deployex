## 1. Running DeployEx and Monitored Elixir Application with Ecto locally

For local testing, the root path used for distribution releases and versions is `/tmp/deployex/bucket`. Follow these steps:

Create the required release folders:
```bash
export monitored_app_name=ectoapp
mkdir -p /tmp/deployex/bucket/dist/${monitored_app_name}
mkdir -p /tmp/deployex/bucket/versions/${monitored_app_name}/local/
```

It is important to note that for local deployments, DeployEx will use the path `/tmp/deployex/varlib` for local storage. This means you can delete the entire folder to reset any local version, history, or configurations.

## 2. Creating an Elixir phoenix app (default name is `ectoapp`)

In this example, we create a brand new application using `mix phx.new` and added the library [Jellyfish](https://github.com/thiagoesteves/jellyfish) for testing hotupgrades.

> [!NOTE]
> A project [ectoapp](https://github.com/thiagoesteves/ectoapp) is also available for consulting

```bash
mix local.hex
mix archive.install hex phx_new
mix phx.new ectoapp
cd ectoapp
mix phx.gen.auth Accounts User users
mix deps.get
mix compile
```

## 3. Add env.sh.eex file in the release folder to configure the OTP distribution

```bash
vi rel/env.sh.eex
# Add the following lines:

#!/bin/sh
# Set a default Erlang cookie value if not provided by ENV VAR.
# This default is temporary; update it using AWS secrets and config provider.
[ -z ${RELEASE_COOKIE} ] && export RELEASE_COOKIE="cookie"
export RELEASE_DISTRIBUTION=sname

# save the file :wq
```

## 4. Configuring your app to allow Hot upgrades (optional)
Add [Jellyfish](https://github.com/thiagoesteves/jellyfish) library __ONLY__ if the application will need hotupgrades
```elixir
def deps do
  [
    {:jellyfish, "~> 0.2.0"}
  ]
end
```

You also need to add the following line in the mix project
```elixir
  def project do
    [
      ...
      releases: [
        ectoapp: [
          steps: [:assemble, &Jellyfish.generate/1, :tar]
        ]
      ],
      ...
    ]
  end
```

Also, make sure you have added the `runtime_tools` to the release so DeployEx can have access to tracing via Observer Web:
```elixir
  def application do
    [
      mod: {Ectoapp.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end
```

Open the `config/prod.exs` and replace the static manifest for a live reload

```elixir
#config :ectoapp, EctoappWeb.Endpoint,
#  cache_static_manifest: "priv/static/cache_manifest.json"
# Since the application is using the Hot upgrade, the manifest cannot be static
config :ectoapp, EctoappWeb.Endpoint,
live_reload: [
  patterns: [
    ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
    ~r"priv/gettext/.*(po)$"
  ]
]
```

## 5. Configuring your app as broadcast mode publishing metrics to DeployEx (optional)
Add [Observer Web](https://github.com/thiagoesteves/observer_web)
```elixir
def deps do
  [
    {:observer_web, "~> 0.1.0"}
  ]
end
```

Open the `config/config.exs` and add the following configuration
```elixir
config :observer_web, ObserverWeb.Telemetry,
  mode: :broadcast
```

Add the migrator file `lib/migrator.ex` that will execute the migrations:

```elixir
defmodule Ectoapp.Migrator do
  @moduledoc false
  @app :ectoapp

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create do
    load_app()

    for repo <- repos() do
      create_database(repo)
    end
  end

  def seed do
    load_app()

    for repo <- repos() do
      seed_database(repo)
    end
  end

  def seed_database(repo) do
    case Ecto.Migrator.with_repo(repo, &eval_seed(&1)) do
      {:ok, {:ok, _fun_return}, _apps} ->
        IO.puts("The seed database for #{inspect(repo)} has been executed with success")
        :ok

      {:ok, {:error, reason}, _apps} ->
        IO.puts(
          "The seed database for #{inspect(repo)} has been failed with reason: #{inspect(reason)}"
        )

        {:error, reason}

      {:error, term} ->
        IO.puts(
          "The seed database for #{inspect(repo)} has been failed with term: #{inspect(term)}"
        )

        {:error, term}
    end
  end

  defp eval_seed(_repo) do
    seeds_file = "#{:code.priv_dir(@app)}/repo/seeds.exs"

    if File.regular?(seeds_file) do
      {:ok, Code.eval_file(seeds_file)}
    else
      {:error, "Seeds file not found."}
    end
  end

  defp create_database(repo) do
    case repo.__adapter__.storage_up(repo.config) do
      :ok ->
        IO.puts("The database for #{inspect(repo)} has been created")

      {:error, :already_up} ->
        IO.puts("The database for #{inspect(repo)} has already been created")

      {:error, term} when is_binary(term) ->
        raise "The database for #{inspect(repo)} couldn't be created: #{term}"

      {:error, term} ->
        raise "The database for #{inspect(repo)} couldn't be created: #{inspect(term)}"
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

## 6. Generate a release
Then you can compile and generate a release
```bash
mix deps.get
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
...
==> ectoapp
Compiling 29 files (.ex)
Generated ectoapp app
Check your digested files at "priv/static"
* assembling ectoapp-0.1.0 on MIX_ENV=prod
* using config/runtime.exs to configure the release at runtime
* creating _build/prod/rel/ectoapp/releases/0.1.0/env.sh
* hot-upgrade Checking if previous versions are available
 versions: ["0.1.0"] current: 0.1.0 - No appups
* hot-upgrade copying release file to /Users/testeves/Workspace/Esl/test/ectoapp/_build/prod/rel/ectoapp/releases/ectoapp-0.1.0.rel
* building /Users/testeves/Workspace/Esl/test/ectoapp/_build/prod/ectoapp-0.1.0.tar.gz
```

Move the release file to the distributed folder and updated the version:
```bash
export app_name=ectoapp
cp _build/prod/${app_name}-0.1.0.tar.gz /tmp/deployex/bucket/dist/${app_name}
echo "{\"version\":\"0.1.0\",\"pre_commands\": [\"eval Ectoapp.Migrator.create\", \"eval Ectoapp.Migrator.migrate\"],\"hash\":\"local\"}" | jq > /tmp/deployex/bucket/versions/${app_name}/local/current.json
```

## 7. Running DeployEx and deploy the app

### Adding an Elixir Monitored Application

The default `dev` application for deployex is `myphoenixapp`. To add another application to monitoring, update the `config/dev.exs` file:

```elixir
config :foundation,
  env: "local",
  base_path: "/tmp/deployex/varlib",
  monitored_app_log_path: "/tmp/deployex/varlog",
  applications: [
    %{
      name: "ectoapp",
      replicas: 2,
      language: "elixir",
      initial_port: 4000,
      env: [
        "SECRET_KEY_BASE=e4CXwPpjrAJp9NbRobS8dXmOHfn0EBpFdhZlPmZo1y3N/BzW9Z/k7iP7FjMk+chi",
        "PHX_SERVER=true",
        "DATABASE_URL=ecto://postgres:postgres@localhost:5432/ectoapp_prod"
      ]
    }
  ]
```

### Running DeployEx

> [!ATTENTION]
> The file `config/dev.exs` contains defaults for local development. Note that these configurations only apply to development environments; production environments require configuration via YAML file.

Move back to the DeployEx project and run the command line: 

```bash
iex --sname deployex --cookie cookie -S mix phx.server
...
[info] Update is needed at sname:  from: <no current set> to: 0.1.0
[info] Full deploy instance: 1 sname: ectoapp-n1g11n
[info] Initializing monitor server for sname: ectoapp-n1g11n language: elixir
[info] Ensure running requested for sname: ectoapp-n1g11n version: 0.1.0
[info]  # Identified executable: /tmp/deployex/varlib/service/ectoapp/ectoapp-n1g11n/current/bin/ectoapp
[info]  # Migration executable: /tmp/deployex/varlib/service/ectoapp/ectoapp-n1g11n/current/bin/ectoapp
[info]  # Executing: eval Ectoapp.Migrator.create
[info]  # Executing: eval Ectoapp.Migrator.migrate
[info]  # Starting application
[info]  # Running sname: ectoapp-n1g11n, monitoring pid = #PID<0.993.0>, OS process = 37468 sname: ectoapp-n1g11n
[info] Initializing Terminal node:  - %{type: "stdout", context: :terminal_logs, sname: "ectoapp-n1g11n"} at process os_pid: 37469
[info] Initializing Terminal node:  - %{type: "stderr", context: :terminal_logs, sname: "ectoapp-n1g11n"} at process os_pid: 37470
[info]  # Application sname: ectoapp-n1wxf5 is running
[info]  # Moving to the next instance: 2

...
iex(deployex@hostname)1>
```

You should then visit the application and check it is running [localhost:5001](http://localhost:5001/). Since you are not using mTLS, the dashboard should look like this:

![No mTLS Dashboard](../../static/deployex_monitoring_ectoapp_no_tls.png)

Note that the __OTP-Nodes are connected__, but the __mTLS is not supported__. The __mTLS__ can be enabled and it will be covered ahead. Leave this terminal running and open a new one to compile and release the monitored app.

## 8. Updating the application

### Full deployment

In this scenario, the existing application will undergo termination, paving the way for the deployment of the new one. It's crucial to maintain the continuous operation of DeployEx throughout this process. Navigate to the `ectoapp` project and increment the version in the `mix.exs` file. Typically, during release execution, the CI/CD pipeline either generates the package from scratch or relies on the precompiled version, particularly for hot-upgrades. If you've incorporated the [Jellyfish](https://github.com/thiagoesteves/jellyfish) library and wish to exclusively create the full deployment package, for this test you must follow the steps: 

1. Remove any previously generated files and generate a new release
```bash
cp ectoapp
rm -rf _build/prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
...
Generated ectoapp app
Check your digested files at "priv/static"
* assembling ectoapp-0.1.1 on MIX_ENV=prod
* using config/runtime.exs to configure the release at runtime
* creating _build/prod/rel/ectoapp/releases/0.1.1/env.sh
* hot-upgrade Checking if previous versions are available
 versions: ["0.1.1"] current: 0.1.1 - No appups
* hot-upgrade copying release file to /Users/testeves/Workspace/Esl/ectoapp/_build/prod/rel/ectoapp/releases/ectoapp-0.1.1.rel
* building /Users/testeves/Workspace/Esl/ectoapp/_build/prod/ectoapp-0.1.1.tar.gz
```

2. Now, *__keep DeployEx running in another terminal__* and copy the release file to the distribution folder and proceed to update the version accordingly:
```bash
export app_name=ectoapp
cp _build/prod/${app_name}-0.1.1.tar.gz /tmp/deployex/bucket/dist/${app_name}
echo "{\"version\":\"0.1.1\",\"pre_commands\": [\"eval Ectoapp.Migrator.create\", \"eval Ectoapp.Migrator.migrate\"],\"hash\":\"local\"}" | jq > /tmp/deployex/bucket/versions/${app_name}/local/current.json
```

3. You should then see the following messages in the DeployEx terminal while updating the app:
```bash

[info] Update is needed at sname: ectoapp-n1g11n from: 0.1.0 to: 0.1.1
[warning] HOT UPGRADE version NOT DETECTED, full deployment required, reason: :not_found
[info] Full deploy instance: 1 sname: ectoapp-5as26p
[info] Requested sname: ectoapp-n1g11n to stop application pid: #PID<0.993.0>
[warning] Remaining beam app removed for sname: ectoapp-n1g11n
[info] Initializing monitor server for sname: ectoapp-5as26p language: elixir
[info] Ensure running requested for sname: ectoapp-5as26p version: 0.1.1
[info]  # Identified executable: /tmp/deployex/varlib/service/ectoapp/ectoapp-5as26p/current/bin/ectoapp
[info]  # Migration executable: /tmp/deployex/varlib/service/ectoapp/ectoapp-5as26p/current/bin/ectoapp
[info]  # Executing: eval Ectoapp.Migrator.create
[info]  # Executing: eval Ectoapp.Migrator.migrate
[info]  # Starting application
[info]  # Running sname: ectoapp-5as26p, monitoring pid = #PID<0.6637.0>, OS process = 40897 sname: ectoapp-5as26p
[info] Initializing Terminal node:  - %{type: "stdout", context: :terminal_logs, sname: "ectoapp-5as26p"} at process os_pid: 40898
[info] Initializing Terminal node:  - %{type: "stderr", context: :terminal_logs, sname: "ectoapp-5as26p"} at process os_pid: 40899
[info]  # Application sname: ectoapp-5as26p is running
[info]  # Moving to the next instance: 2
...
```

### Hot-upgrades

For this scenario, the project must first be compiled to the current version and subsequently compiled for the version it's expected to update to. The `current.json` file deployed includes the git hash representing the current application version. In this local testing phase, it suffices to compile for the previous version, such as `0.1.1`, and the subsequent version, like `0.1.2`, so the necessary files will be automatically populated.

1. Since the application is already compiled for `0.1.1`, change the `mix.exs` to `0.1.2`, apply any other changes if you want to test and execute the command:
```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
...
Generated ectoapp app
Check your digested files at "priv/static"
* assembling ectoapp-0.1.2 on MIX_ENV=prod
* using config/runtime.exs to configure the release at runtime
* creating _build/prod/rel/ectoapp/releases/0.1.2/env.sh
* hot-upgrade Checking if previous versions are available
 versions: ["0.1.1", "0.1.2"] current: 0.1.2 - appups: ectoapp/rel/appups/
* hot-upgrade copying release file to /Users/testeves/Workspace/Esl/test/ectoapp/_build/prod/rel/ectoapp/releases/ectoapp-0.1.2.rel
* building /Users/testeves/Workspace/Esl/test/ectoapp/_build/prod/ectoapp-0.1.2.tar.gz
```

2. Now, copy the release file to the distribution folder and proceed to update the version accordingly:
```bash
export app_name=ectoapp
cp _build/prod/${app_name}-0.1.2.tar.gz /tmp/deployex/bucket/dist/${app_name}
echo "{\"version\":\"0.1.2\",\"pre_commands\": [\"eval Ectoapp.Migrator.create\", \"eval Ectoapp.Migrator.migrate\"],\"hash\":\"local\"}" | jq > /tmp/deployex/bucket/versions/${app_name}/local/current.json
```

You can then check that DeployEx had executed a hot upgrade in the application:

```bash
[info] Update is needed at sname: ectoapp-5as26p from: 0.1.1 to: 0.1.2
[warning] HOT UPGRADE version DETECTED - [%{"from" => "0.1.1", "name" => "ectoapp", "to" => "0.1.2"}]
[info]  # Migration executable: /tmp/deployex/varlib/service/ectoapp/ectoapp-5as26p/new/bin/ectoapp
[info]  # Executing: eval Ectoapp.Migrator.create
[info]  # Executing: eval Ectoapp.Migrator.migrate
[info] Hot upgrade instance: 1 sname: ectoapp-5as26p
[info] Unpacked successfully: ~c"0.1.2"
[info] Installed Release: ~c"0.1.2"
[info] Made release permanent: 0.1.2
[info] Release upgrade executed with success at node: ectoapp-5as26p@MacBookPro from: 0.1.1 to: 0.1.2
[info]  # Moving to the next instance: 2
...
```

you can check that the version and the deployment status has changed in the dashboard:

![No mTLS Dashboard](../../static/deployex_monitoring_ectoapp_hot_upgrade.png)


## 9. 🔑 Enhancing OTP Distribution Security with mTLS

In order to improve security, mutual TLS (`mTLS` for short) can be employed to encrypt communication during OTP distribution. To implement this, follow these steps:

1. Generate the necessary certificates, DeployEx has a good examples of how to create self-signed tls certificates:
```bash
cd deployex
./tls-distribution-certs
```

2. Copy the generated certificates to the `/tmp` folder:
```bash
cp ca.crt /tmp
cp deployex.crt /tmp
cp deployex.key /tmp
```

3. Create the `inet_tls.conf` file with the appropriate paths, utilizing the command found in `rel/env.sh.eex` in deployex project:
```bash
export DEPLOYEX_OTP_TLS_CERT_PATH=/tmp

test -f /tmp/inet_tls.conf || (umask 277
 cd /tmp
 cat >inet_tls.conf <<EOF
[
  {server, [
    {certfile, "${DEPLOYEX_OTP_TLS_CERT_PATH}/deployex.crt"},
    {keyfile, "${DEPLOYEX_OTP_TLS_CERT_PATH}/deployex.key"},
    {cacertfile, "${DEPLOYEX_OTP_TLS_CERT_PATH}/ca.crt"},
    {verify, verify_peer},
    {secure_renegotiate, true}
  ]},
  {client, [
    {certfile, "${DEPLOYEX_OTP_TLS_CERT_PATH}/deployex.crt"},
    {keyfile, "${DEPLOYEX_OTP_TLS_CERT_PATH}/deployex.key"},
    {cacertfile, "${DEPLOYEX_OTP_TLS_CERT_PATH}/ca.crt"},
    {verify, verify_peer},
    {secure_renegotiate, true},
    {server_name_indication, disable}
  ]}
].
EOF
)
```

4. Ensure that `ectoapp` also utilizes the same options and certificate by updating `rel/env.sh.eex`:
```bash
cd ectoapp
vi rel/env.sh.eex
# Add the following line
#!/bin/sh
export ELIXIR_ERL_OPTIONS="-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf"
# save the file :q
```

> [!ATTENTION]
> Since tls is enabled during the startup of the application, a full deploy is required, remove `_build` folder before `mix release`.

5. To enable `mTLS` for DeployEx, set the appropriate Erlang options before running the application in the terminal:
```bash
ELIXIR_ERL_OPTIONS="-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf -setcookie cookie" iex --sname deployex -S mix phx.server
```

After making these changes, create and publish a new version `0.1.3` for `ectoapp` and run the DeployEx with the command from item 5. After the deployment, you should see the following dashboard:

![mTLS Dashboard](../../static/deployex_monitoring_ectoapp_tls.png)

> [!ATTENTION]
> Ensure that the cookie is properly set