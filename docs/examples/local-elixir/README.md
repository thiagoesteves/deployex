# 🏠 Running DeployEx and Monitored Elixir Application locally

For local testing, the root path used for distribution releases and versions is `/tmp/{monitored_app}`. Follow these steps:

Create the required release folders:
```bash
export monitored_app_name=myphoenixapp
mkdir -p /tmp/${monitored_app_name}/dist/${monitored_app_name}
mkdir -p /tmp/${monitored_app_name}/versions/${monitored_app_name}/local/
```

It is important to note that for local deployments, DeployEx will use the path `/tmp/deployex` for local storage. This means you can delete the entire folder to reset any local version, history, or configurations.

## Creating an Elixir phoenix app (default name is `myphoenixapp`)

In this example, we create a brand new application using `mix phx.new` and added the library [Jellyfish](https://github.com/thiagoesteves/jellyfish) for testing hotupgrades.

```bash
mix local.hex
mix archive.install hex phx_new
mix phx.new myphoenixapp --no-ecto
cd myphoenixapp
```

## Add env.sh.eex file in the release folder to configure the OTP distribution

```bash
vi rel/env.sh.eex
# Add the following lines:

#!/bin/sh
# Set a default Erlang cookie value if not provided by ENV VAR.
# This default is temporary; update it using AWS secrets and config provider.
[ -z ${RELEASE_COOKIE} ] && export RELEASE_COOKIE="cookie"
export RELEASE_DISTRIBUTION=sname
[ -z ${RELEASE_NODE_SUFFIX} ] && export RELEASE_NODE_SUFFIX=""
export RELEASE_NODE=<%= @release.name %>${RELEASE_NODE_SUFFIX}

# save the file :wq
```

## The next steps are needed ONLY for Hot upgrades
Add [Jellyfish](https://github.com/thiagoesteves/jellyfish) library __ONLY__ if the application will need hotupgrades
```elixir
def deps do
  [
    {:jellyfish, "~> 0.1.3"}
  ]
end
```

You also need to add the following lines in the mix project
```elixir
  def project do
    [
      ...
      compilers: Mix.compilers() ++ [:gen_appup, :appup],
      releases: [
        myphoenixapp: [
          steps: [:assemble, &Jellyfish.Releases.Copy.relfile/1, :tar]
        ]
      ],
      ...
    ]
  end
```
Open the `config/prod.exs` and replace the static manifest for a live reload

```elixir
#config :myphoenixapp, MyphoenixappWeb.Endpoint,
#  cache_static_manifest: "priv/static/cache_manifest.json"
# Since the application is using the Hot upgrade, the manifest cannot be static
config :myphoenixapp, MyphoenixappWeb.Endpoint,
live_reload: [
  patterns: [
    ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
    ~r"priv/gettext/.*(po)$"
  ]
]
```

## Generate a release
Then you can compile and generate a release
```bash
mix deps.get
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
...
No appups, nothing to move to the release
* assembling myphoenixapp-0.1.0 on MIX_ENV=prod
* using config/runtime.exs to configure the release at runtime
* hot-upgrade copying release file to /Users/testeves/Workspace/Esl/myphoenixapp/_build/prod/rel/myphoenixapp/releases/myphoenixapp-0.1.0.rel
* building /Users/testeves/Workspace/Esl/myphoenixapp/_build/prod/myphoenixapp-0.1.0.tar.gz
```

Move the release file to the distributed folder and updated the version:
```bash
export app_name=myphoenixapp
cp _build/prod/${app_name}-0.1.0.tar.gz /tmp/${app_name}/dist/${app_name}
echo "{\"version\":\"0.1.0\",\"pre_commands\": [],\"hash\":\"local\"}" | jq > /tmp/${app_name}/versions/${app_name}/local/current.json
```

## Running DeployEx and deploy the app

Move back to the DeployEx project and run the command line with the required ENV vars. 

*__NOTE:  All env vars that are available for DeployEx will also be available to the `monitored_app`__*
```bash
export SECRET_KEY_BASE=e4CXwPpjrAJp9NbRobS8dXmOHfn0EBpFdhZlPmZo1y3N/BzW9Z/k7iP7FjMk+chi
export PHX_SERVER=true
export DATABASE_URL=ecto://postgres:postgres@localhost:5432/myphoenixapp_prod # In case your monitored add is using ecto
iex --sname deployex --cookie cookie -S mix phx.server
...

[info] Update is needed at instance: 1 from: <no current set> to: 0.1.0.
[warning] HOT UPGRADE version NOT DETECTED, full deployment required, result: []
[info] Full deploy instance: 1 deploy_ref: 32656.
[info] Initialising monitor server for instance: 1
[info] Ensure running requested for instance: 1 version: 0.1.0
[info]  # Identified executable: /tmp/deployex/varlib/service/myphoenixapp/1/current/bin/myphoenixapp
[info]  # Starting application
[info]  # Running instance: 1, monitoring pid = #PID<0.790.0>, OS process = 36891 deploy_ref: 32656.
[info]  # Application instance: 1 is running
[info]  # Moving to the next instance: 2
...
iex(deployex@hostname)1>
```

You should then visit the application and check it is running [localhost:5001](http://localhost:5001/). Since you are not using mTLS, the dashboard should look like this:

![No mTLS Dashboard](../../static/deployex_monitoring_app_no_tls.png)

Note that the __OTP-Nodes are connected__, but the __mTLS is not supported__. The __mTLS__ can be enabled and it will be covered ahead. Leave this terminal running and open a new one to compile and release the monitored app.

## Updating the application

### Full deployment

In this scenario, the existing application will undergo termination, paving the way for the deployment of the new one. It's crucial to maintain the continuous operation of DeployEx throughout this process. Navigate to the `myphoenixapp` project and increment the version in the `mix.exs` file. Typically, during release execution, the CI/CD pipeline either generates the package from scratch or relies on the precompiled version, particularly for hot-upgrades. If you've incorporated the [Jellyfish](https://github.com/thiagoesteves/jellyfish) library and wish to exclusively create the full deployment package, for this test you must follow the steps: 

1. Remove any previously generated files and generate a new release
```bash
cp myphoenixapp
rm -rf _build/prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
...
Generated myphoenixapp app
No appups, nothing to move to the release
Check your digested files at "priv/static"
No appups, nothing to move to the release
* assembling myphoenixapp-0.1.1 on MIX_ENV=prod
* using config/runtime.exs to configure the release at runtime
* hot-upgrade copying release file to /Users/testeves/Workspace/Esl/myphoenixapp/_build/prod/rel/myphoenixapp/releases/myphoenixapp-0.1.1.rel
* building /Users/testeves/Workspace/Esl/myphoenixapp/_build/prod/myphoenixapp-0.1.1.tar.gz
```

2. Now, *__keep DeployEx running in another terminal__* and copy the release file to the distribution folder and proceed to update the version accordingly:
```bash
export app_name=myphoenixapp
cp _build/prod/${app_name}-0.1.1.tar.gz /tmp/${app_name}/dist/${app_name}
echo "{\"version\":\"0.1.1\",\"pre_commands\": [],\"hash\":\"local\"}" | jq > /tmp/${app_name}/versions/${app_name}/local/current.json
```

3. You should then see the following messages in the DeployEx terminal while updating the app:
```bash
[info] Update is needed at instance: 1 from: 0.1.0 to: 0.1.1.
[warning] HOT UPGRADE version NOT DETECTED, full deployment required, result: []
[info] Full deploy instance: 1 deploy_ref: 37406.
[info] Requested instance: 1 to stop application pid: #PID<0.790.0>
[warning] Remaining beam app removed for instance: 1
[info] Initialising monitor server for instance: 1
[info] Ensure running requested for instance: 1 version: 0.1.1
[info]  # Identified executable: /tmp/deployex/varlib/service/myphoenixapp/1/current/bin/myphoenixapp
[info]  # Starting application
[info]  # Running instance: 1, monitoring pid = #PID<0.843.0>, OS process = 37992 deploy_ref: 37406.
[info]  # Application instance: 1 is running
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
Generated myphoenixapp app
You can find your generated appups in rel/appups/myphoenixapp/ with the .appup extension
Check your digested files at "priv/static"
You can find your generated appups in rel/appups/myphoenixapp/ with the .appup extension
* assembling myphoenixapp-0.1.2 on MIX_ENV=prod
* using config/runtime.exs to configure the release at runtime
* hot-upgrade copying release file to /Users/testeves/Workspace/Esl/myphoenixapp/_build/prod/rel/myphoenixapp/releases/myphoenixapp-0.1.2.rel
* building /Users/testeves/Workspace/Esl/myphoenixapp/_build/prod/myphoenixapp-0.1.2.tar.gz
```

2. Now, copy the release file to the distribution folder and proceed to update the version accordingly:
```bash
export app_name=myphoenixapp
cp _build/prod/${app_name}-0.1.2.tar.gz /tmp/${app_name}/dist/${app_name}
echo "{\"version\":\"0.1.2\",\"pre_commands\": [],\"hash\":\"local\"}" | jq > /tmp/${app_name}/versions/${app_name}/local/current.json
```

You can then check that DeployEx had executed a hot upgrade in the application:

```bash
[info] Update is needed at instance: 1 from: 0.1.1 to: 0.1.2.
[warning] HOT UPGRADE version DETECTED, from: 0.1.1 to: 0.1.2
[info] Hot upgrade instance: 1 deploy_ref: 37406.
[info] Unpacked successfully: ~c"0.1.2"
[info] Installed Release: ~c"0.1.2"
[info] Made release permanent: 0.1.2
[info] Release upgrade executed with success at instance: 1 from: 0.1.1 to: 0.1.2
[info]  # Moving to the next instance: 2
...
```

you can check that the version and the deployment status has changed in the dashboard:

![No mTLS Dashboard](../../static/deployex_monitoring_app_hot_upgrade.png)


## 🔑 Enhancing OTP Distribution Security with mTLS

In order to improve security, mutual TLS (`mTLS` for short) can be employed to encrypt communication during OTP distribution. To implement this, follow these steps:

1. Generate the necessary certificates, DeployEx has a good examples of how to create self-signed tls certificates:
```bash
cd deployex
make tls-distribution-certs
```

2. Copy the generated certificates to the `/tmp` folder:
```bash
cp ca.crt /tmp
cp deployex.crt /tmp
cp deployex.key /tmp
```

3. Create the `inet_tls.conf` file with the appropriate paths, utilizing the command found in `rel/env.sh.eex`:
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

4. Ensure that `myphoenixapp` also utilizes the same options and certificate by updating `rel/env.sh.eex`:
```bash
cd myphoenixapp
vi rel/env.sh.eex
# Add the following line
#!/bin/sh
export ELIXIR_ERL_OPTIONS="-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf"
# save the file :q
```

5. To enable `mTLS` for DeployEx, set the appropriate Erlang options before running the application in the terminal:
```bash
ELIXIR_ERL_OPTIONS="-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf -setcookie cookie" iex --sname deployex -S mix phx.server
```

After making these changes, create and publish a new version `0.1.3` for `myphoenixapp` and run the DeployEx with the command from item 5. After the deployment, you should see the following dashboard:

![mTLS Dashboard](../../static/deployex_monitoring_app_tls.png)

> [!ATTENTION]
> Ensure that the cookie is properly set