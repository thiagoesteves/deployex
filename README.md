# Deployex

Deployex is a lightweight tool designed for managing deployments in Elixir applications without relying on additional deployment tools like Docker or Kubernetes. Its primary goal is to utilize the mix release package for executing full deployments or hot-upgrades, depending on the package's content, while leveraging OTP distribution for monitoring and data extraction.

Deployex acts as a central deployment runner, gathering crucial deployment data such as the current version and release package contents. The content of the release package enables it to run for a full deployment or a hot-upgrade. Meanwhile, on the development front, your CI/CD pipeline takes charge of crafting and updating packages for the target release. This integration ensures that Deployex is always equipped with the latest packages, ready to facilitate deployments.

Deployex is currently used by [Calori Web Server](https://github.com/thiagoesteves/calori) and you can check its [deployment](https://deployex.calori.com.br).

![Deployment Architecture](/docs/deployex.png)

Upon deployment, the following dashboard becomes available, offering access to logs for both Deployex and monitored applications, along with an IEX terminal."

![Running with no monitored apps](/docs/deployex_server.png)

## Features to be worked on

The Deployex project is still very new and requires the addition of numerous features to become a comprehensive deployment solution. Below are some of the features it can incorporate:

- [ ] Execute migrations before full deployment
- [ ] OTP Distribution monitoring for health checks
- [ ] Full deployment rollback functionality

## Getting Started

### Running the application

You can kickstart the setup with the following commands, the default number of replicas is 3:
```bash
mix deps.get
iex --sname deployex --cookie cookie -S mix phx.server
[info] Initialising deployment server
[info] Running DeployexWeb.Endpoint with Bandit 1.5.3 at 127.0.0.1:5001 (http)
[info] Access DeployexWeb.Endpoint at http://localhost:5001
[info] Initialising monitor server for instance: 1
[info] No version set, not able to run_service
[info] Initialising monitor server for instance: 2
[info] No version set, not able to run_service
[info] Initialising monitor server for instance: 3
[info] No version set, not able to run_service
[watch] build finished, watching for changes...
Erlang/OTP 26 [erts-14.1.1] [source] [64-bit] [smp:10:10] [ds:10:10:10] [async-threads:1] [jit]

Interactive Elixir (1.16.0) - press Ctrl+C to exit (type h() ENTER for help)

Rebuilding...

Done in 434ms.
[error] Error while trying to connect with node: :"myphoenixapp-1@hostname" reason: false
```

Now you can visit [`localhost:5001`](http://localhost:5001) from your browser. You should expect the following dashboard:

![Empty Dashboard](/docs/deployex_no_monitoring_app.png)

*__PS: The error message in the CLI is due to no monitored app is available to be deployed. If you want to proceed for a local test, follow the steps at [Running Deployex and Monitored app locally](##_running_deployex_and_monitored_app_locally). Also, it is important to note that the distribution will be required so this is the reason to add `-sname deployex` in the command.__*

### How Deployex handles monitored application Version/Release

The Deployex app expects a `current.json` file to be available, which contains version and hash information. This file is mandatory for full deployment and hot upgrades.

#### Version file (current.json) 

Expected location in the storage folder:
```bash
# production path
s3://{monitored_app}-{env}-distribution/versions/{monitored_app}/{env}/current.json
# local test path
/tmp/{monitored_app}/versions/{monitored_app}/{env}/current.json
```

Expected Json format:
```bash
{
  "version": "1.0.0",
  "hash": "local"
}
```

Once the file is captured, the deployment will start if no app is running or if the current app is running with a version that differs from the `current.json` file.

#### Release package

Expected location in the storage folder:
```bash
# production path
s3://{monitored_app}-{env}-distribution/dist/{monitored_app}/{monitored_app}-{version}.tar.gz
# local test path
/tmp/{monitored_app}/dist/{monitored_app}/{monitored_app}-{version}.tar.gz
```

## Environment Variables

Deployex application typically requires several environment variables to be defined for proper operation. Ensure that you have the following environment variables set when running in production where the ones that have a default value available are not required:

| ENV NAME   |      EXAMPLE      |  SOURCE |  DEFAULT | DESCRIPTION |
|----------|-------------|------:|------|------|
| __DEPLOYEX_SECRET_KEY_BASE__ | 42otsNl...Fpq3dIJ02 | aws secrets | -/- | secret key used for encryption |
| __DEPLOYEX_ERLANG_COOKIE__ | cookie | aws secrets | -/- | erlang cookie |
| __DEPLOYEX_MONITORED_APP_NAME__ | myphoenixapp | system ENV | -/- | Monitored app name |
| __DEPLOYEX_CLOUD_ENVIRONMENT__ | prod | system ENV | -/- | cloud env name |
| __AWS_REGION__ | us-east2 | system ENV | -/- | the aws region |
| __DEPLOYEX_PHX_HOST__ | example.com | system ENV | -/- | The hostname for your application |
| __DEPLOYEX_PHX_PORT__ | 5001 | system ENV | 5001 | The port on which the application will run |
| __DEPLOYEX_PHX_SERVER__ | true | system ENV | true | enable/disable server |
| __DEPLOYEX_STORAGE_ADAPTER__ | local | system ENV | s3 | storage adapter type |
| __DEPLOYEX_MONITORED_APP_PORT__ | 4000 | system ENV | 4000 | the aws region |
| __DEPLOYEX_MONITORED_REPLICAS__ | 2 | system ENV | 3 | the aws region |

For local testing, these variables are not expected or set to default values.

## Production installation

If you plan to install Deployex directly on an Ubuntu server, you can use the [installer script](/devops/installer/deployex.sh) included in the release package. For an example, refer to the [Calori Web Server](https://github.com/thiagoesteves/calori). As of now, the release and installation only supports Ubuntu versions 20.04 and 22.04, but you can compile and install manually in your target system.

## Running Deployex and Monitored app locally

For local testing, the root path used is `/tmp/{monitored_app}`. Follow these steps:

Create the required storage folders:
```bash
export monitored_app_name=myphoenixapp
mkdir -p /tmp/${monitored_app_name}/dist/${monitored_app_name}
mkdir -p /tmp/${monitored_app_name}/versions/${monitored_app_name}/local/
```

Go to the application you want to deploy/monitor and create a release. In this example, we create a brand new application using phx.new and added the library [Jellyfish](https://github.com/thiagoesteves/jellyfish) for testing hotupgrades.

### Creating an Elixir phoenix app (default name is `myphoenixapp`)

```bash
mix local.hex
mix archive.install hex phx_new
mix phx.new myphoenixapp --no-ecto
cd myphoenixapp
```

### Add env.sh.eex file in the release folder to configure the OTP distribution

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

### The next steps are needed ONLY for Hot upgrades
Add [Jellyfish](https://github.com/thiagoesteves/jellyfish) library __ONLY__ if the application will need hotupgrades
```elixir
def deps do
  [
    {:jellyfish, "~> 0.1.2"}
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

### Generate a release
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
cp _build/prod/myphoenixapp-0.1.0.tar.gz /tmp/myphoenixapp/dist/myphoenixapp
echo "{\"version\":\"0.1.0\",\"hash\":\"local\"}" | jq > /tmp/myphoenixapp/versions/myphoenixapp/local/current.json
```

### Running Deployex and deploy the app

Move back to the deployex project and run the command line with the required ENV vars. 

*__NOTE:  All env vars that are available for deployex will also be available to the `monitored_app`__*
```bash
export SECRET_KEY_BASE=e4CXwPpjrAJp9NbRobS8dXmOHfn0EBpFdhZlPmZo1y3N/BzW9Z/k7iP7FjMk+chi
export PHX_SERVER=true
iex --sname deployex --cookie cookie -S mix phx.server
...

[warning] HOT UPGRADE version NOT DETECTED, full deployment required, result: {:error, :no_match_versions}
[info] Requested instance: 1 to stop but application is not running.
[warning] No previous version set
[info] Ensure running requested for instance: 1 version: 0.1.0
[info]  # Starting /tmp/deployex/varlib/service/myphoenixapp/1/current/bin/myphoenixapp...
[info]  # Running instance: 1, monitoring pid = #PID<0.779.0>, OS process id = 11211.
iex(deployex@hostname)1>
```

You should then visit the application and check it is running [localhost:5001](http://localhost:5001/). Since you are not using mTLS, the dashboard should look like this:

![No mTLS Dashboard](/docs/deployex_monitoring_app_no_tls.png)

Note that the __OTP-Nodes are connected__, but the __mTLS is not supported__. The __mTLS__ can be enabled and it will be covered ahead. Leave this terminal running and open a new one to compile and release the monitored app.

### Updating the application

#### Full deployment

In this scenario, the existing application will undergo termination, paving the way for the deployment of the new one. It's crucial to maintain the continuous operation of Deployex throughout this process. Navigate to the `myphoenixapp` project and increment the version in the `mix.exs` file. Typically, during release execution, the CI/CD pipeline either generates the package from scratch or relies on the precompiled version, particularly for hot-upgrades. If you've incorporated the [Jellyfish](https://github.com/thiagoesteves/jellyfish) library and wish to exclusively create the full deployment package, for this test you must follow the steps: 

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

2. Now, *__keep Deployex running in another terminal__* and copy the release file to the distribution folder and proceed to update the version accordingly:
```bash
cp _build/prod/myphoenixapp-0.1.1.tar.gz /tmp/myphoenixapp/dist/myphoenixapp
echo "{\"version\":\"0.1.1\",\"hash\":\"local\"}" | jq > /tmp/myphoenixapp/versions/myphoenixapp/local/current.json
```

3. You should then see the following messages in the Deployex terminal while updating the app:
```bash
[info] Application instance: 1 is running
[info] Application instance: 2 is running
[info] Application instance: 3 is running
[info] Update is needed at instance: 1 from: 0.1.0 to: 0.1.1.
[warning] HOT UPGRADE version NOT DETECTED, full deployment required, result: []
[info] Requested instance: 1 to stop application pid: #PID<0.912.0>
[warning] Application instance: 1 with pid: #PID<0.912.0> being stopped by reason: :normal
[info] Ensure running requested for instance: 1 version: 0.1.1
[info]  # Starting /tmp/deployex/varlib/service/myphoenixapp/1/current/bin/myphoenixapp...
[info]  # Running instance: 1, monitoring pid = #PID<0.1019.0>, OS process id = 29793.
```

#### Hot-upgrades

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
cp _build/prod/myphoenixapp-0.1.2.tar.gz /tmp/myphoenixapp/dist/myphoenixapp
echo "{\"version\":\"0.1.2\",\"hash\":\"local\"}" | jq > /tmp/myphoenixapp/versions/myphoenixapp/local/current.json
```

You can then check that deployex had executed a hot upgrade in the application:

```bash
[info] Update is needed at instance: 1 from: 0.1.1 to: 0.1.2.
[warning] HOT UPGRADE version DETECTED, from: 0.1.1 to: 0.1.2
[info] Unpacked successfully: ~c"0.1.2"
[info] Installed Release: ~c"0.1.2"
[info] Made release permanent: 0.1.2
[info] Release upgrade executed with success at instance: 1 from: 0.1.1 to: 0.1.2
```

you can check that the version and the deployment status has changed in the dashboard:

![No mTLS Dashboard](/docs/deployex_monitoring_app_hot_upgrade.png)


### Enhancing OTP Distribution Security with mTLS

In order to improve security, mutual TLS (`mTLS` for short) can be employed to encrypt communication during OTP distribution. To implement this, follow these steps:

1. Generate the necessary certificates:
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

4. To enable `mTLS` for deployex, set the appropriate Erlang options before running the application in the terminal:
```bash
ELIXIR_ERL_OPTIONS="-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf -setcookie cookie" iex --sname deployex -S mix phx.server
```

5. Ensure that `myphoenixapp` also utilizes the same options and certificate by updating `rel/env.sh.eex`:
```bash
cd myphoenixapp
vi rel/env.sh.eex
# Add the following line
#!/bin/sh
export ELIXIR_ERL_OPTIONS="-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf"
# save the file :q
```
After making these changes, create and publish a new version `0.1.3` for `myphoenixapp` and run the deployex with the command from item 4. After the deployment, you should see the follwoing dashboard:

![mTLS Dashboard](/docs/deployex_monitoring_app_tls.png)

*__ATTENTION: Ensure that the cookie is properly set__*

## Throubleshooting

### Accessing deployex logs

```bash
# production
tail -f /var/log/deployex/deployex-stdout.log
tail -f /var/log/deployex/deployex-stderr.log
# local test
# not available when running as dev env
```

### Connecting to the deployex IEX CLI

```bash
export RELEASE_NODE_SUFFIX=""
export RELEASE_COOKIE=cookie
# production
/opt/deployex/bin/deployex remote
# local test
# not available when running as dev env
```

### Accessing monitored app logs

```bash
export instance=1
export monitored_app_name=myphoenixapp
# production
tail -f /var/log/${monitored_app_name}/${monitored_app_name}-${instance}-stdout.log
tail -f /var/log/${monitored_app_name}/${monitored_app_name}-${instance}-stderr.log
# local test
tail -f /tmp/${monitored_app_name}/${monitored_app_name}/${monitored_app_name}-${instance}-stdout.log
tail -f /tmp/${monitored_app_name}/${monitored_app_name}/${monitored_app_name}-${instance}-stderr.log
```

### Connecting to the monitored app IEX CLI

```bash
export instance=1
export monitored_app_name=myphoenixapp
export RELEASE_NODE_SUFFIX=-${instance}
export RELEASE_COOKIE=cookie
# production
/var/lib/deployex/service/${monitored_app_name}/${instance}/current/bin/${monitored_app_name} remote
# local test
/tmp/deployex/varlib/service/${monitored_app_name}/${instance}/current/bin/${monitored_app_name} remote
```

## How Deployex handles services

### Full deployment

Deployex operates by monitoring applications and versions using folders and files, treating the monitored app as a service. The deployment process involves several steps to ensure smooth transitions:

1. *__Download and Unpack the New Version:__*
 The new version of the application is downloaded and unpacked into the `new` service folder, ready for deployment.
2. *__Check if the release contain a hot-upgrade or full deployment:__*
 Deployex will check the release file received and if it is a full deployment, goes to the step 3 .
3. *__Stop the Current Application:__*
The currently running application instance is stopped to prepare for the new deployment.
4. *__Delete the Previous Service Folder:__*
 The `previous` service folder, containing the previous version of the application, is deleted to make space for the new version.
5. *__Move the Current Service:__*
 The `current` service folder, representing the current version of the application, is moved to the `previous` service folder. Simultaneously, the `new` service folder is moved to become the new `current` service folder.
6. *__Start the Application:__*
 Finally, the application is started using the version now residing in the `current` service folder, ensuring that the latest version is active and operational.

By following this process, Deployex facilitates deployments, ensuring that applications are updated while minimizing downtime.

For the test environment:
```bash
/tmp/deployex/varlib/service/${monitored_app}/${instance}/previous/${monitored_app}
/tmp/deployex/varlib/service/${monitored_app}/${instance}/new/${monitored_app}
/tmp/deployex/varlib/service/${monitored_app}/${instance}/current/${monitored_app}
```

For production environment:
```bash
/var/lib/deployex/service/${monitored_app}/${instance}/previous/${monitored_app}
/var/lib/deployex/service/${monitored_app}/${instance}/new/${monitored_app}
/var/lib/deployex/service/${monitored_app}/${instance}/current/${monitored_app}
```

### Hot-upgrades

For this scenario, there will be no moving files/folders since the target is to keep the current service folder updated. The sequence is:

1. *__Download and Unpack the New Version:__*
 The new version of the application is downloaded and unpacked into the `new` service folder, ready for deployment.
2. *__Check if the release contain a hot-upgrade or full deployment:__*
 Deployex will check the release file received and if it is a hot-upgrade, goes to the step 3 .
3. *__Execute the Hotupgrade checks and verification__*
 Deployex will try to run the hotupgrade sequence and if succeeds, it makes the changes permanent. Inc ase of failure, it tries to execute a full deployment with the same release file.


