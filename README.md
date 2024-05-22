# Deployex

Deployex is a lightweight tool designed for managing deployments in Elixir applications without relying on additional deployment tools like Docker or Kubernetes. Its primary goal is to utilize the mix release package for executing full deployments or hot-upgrades, depending on the package's content, while leveraging OTP distribution for monitoring and data extraction.

Deployex acts as a central deployment runner, gathering crucial deployment data such as the current version and release package contents. The content of the release package enables it to run for a full deployment or a hot-upgrade. Meanwhile, on the development front, your CI/CD pipeline takes charge of crafting and updating packages for the target release. This integration ensures that Deployex is always equipped with the latest packages, ready to facilitate deployments.

Deployex is currently used by [Calori Web Server](https://github.com/thiagoesteves/calori).

![Deployment Architecture](/docs/deployex.png)

## Features to be worked on

The Deployex project is still very new and requires the addition of numerous features to become a comprehensive deployment solution. Below are some of the features it can incorporate:

- [X] Convert project to a Phoenix app and add a dashboard view status
- [ ] Phoenix Aapp: Add log view tab
- [ ] Phoenix Aapp: Add iex CLI tab
- [ ] Execute migrations before full deployment
- [ ] OTP Distribution monitoring for health checks
- [ ] Full deployment rollback functionality

## Getting Started

### Running the application

You can kickstart the setup with the following commands:
```bash
mix deps.get
iex --sname deployex -S mix phx.server
[info] No version set, not able to start_service
[info] Running DeployexWeb.Endpoint with Bandit 1.5.2 at 127.0.0.1:5001 (http)
[info] Access DeployexWeb.Endpoint at http://localhost:5001
[watch] build finished, watching for changes...
Erlang/OTP 26 [erts-14.1.1] [source] [64-bit] [smp:10:10] [ds:10:10:10] [async-threads:1] [jit]

Interactive Elixir (1.16.0) - press Ctrl+C to exit (type h() ENTER for help)

Rebuilding...

Done in 166ms.
[error] Invalid version map at: /tmp/myphoenixapp/versions/myphoenixapp/local/current.json reason: enoent
```

Now you can visit [`localhost:5000`](http://localhost:5001) from your browser. You shold see as per the picture:

![Running with no monitored apps](/docs/deployex_server.png)

*__PS: The error message in the CLI is due to no monitored app is available to be deployed. If you want to proceed for a local test, follow the next steps. Also, it is important to note that the distribution will be required so this is the reason to add `-sname deployex` in the command.__*

### How Deployex handles application Version/Release

The Deployex app expects a `current.json` file to be present, which contains version and hash information. This file is mandatory for deployment and hot upgrades.

#### Version file (current.json) 

Expected location in the storage folder:
```bash
# production
{s3}/versions/{monitored_app}/{env}/current.json
# local test
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
# production
{s3}/dist/{monitored_app}/{monitored_app}-{version}.tar.gz
# local test
/tmp/{monitored_app}/dist/{monitored_app}/{monitored_app}-{version}.tar.gz
```

## Expected configuration for production release

The following ENV vars are expected to be defined for production:
```bash
DEPLOYEX_SECRET_KEY_BASE=xxxxxxx <--- This secret is expected from AWS secrets
DEPLOYEX_ERLANG_COOKIE=xxxxxx <--- This secret is expected from AWS secrets
DEPLOYEX_MONITORED_APP_NAME=myphoenixapp
DEPLOYEX_STORAGE_ADAPTER=s3
DEPLOYEX_CLOUD_ENVIRONMENT=prod
DEPLOYEX_PHX_SERVER=true
DEPLOYEX_PHX_HOST=example.com
DEPLOYEX_PHX_PORT=5001
AWS_REGION=us-east2
```

For local testing, these variables are not expected or set to default values.

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
export RELEASE_COOKIE="cookie"
export RELEASE_DISTRIBUTION=sname
export RELEASE_NODE=<%= @release.name %>

# save the file :wq
```

### The next steps are needed only for Hot upgrades
Add [Jellyfish](https://github.com/thiagoesteves/jellyfish) library ONLY if the application will need hotupgrades
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
iex --sname deployex -S mix phx.server

...

11:18:31.380 [info] module=Deployex.Deployment function=run_check/1 pid=<0.229.0>  Update is needed from <no current set> to 0.1.0.
11:18:31.592 [warning] module=Deployex.Upgrade function=check/3 pid=<0.229.0>  HOT UPGRADE version NOT DETECTED, full deployment required, result: {:error, :no_match_versions}
11:18:31.592 [info] module=Deployex.Monitor function=handle_call/3 pid=<0.230.0>  Requested to stop but application is not running.
11:18:32.103 [info] module=Deployex.Monitor function=start_service/2 pid=<0.230.0>  Ensure running requested for version: 0.1.0
11:18:32.104 [info] module=Deployex.Monitor function=start_service/2 pid=<0.230.0>   - Starting /tmp/deployex/varlib/service/myphoenixapp/current/bin/myphoenixapp...
11:18:32.106 [info] module=Deployex.Monitor function=start_service/2 pid=<0.230.0>   - Running, monitoring pid = #PID<0.248.0>, OS process id = 7001.
iex(deployex@hostname)1>
```

__You then need to set the cookie (the same for the monitored app)__:
```bash
iex(deployex@hostname)1> Node.set_cookie :cookie
true
```

You should then visit the application and check it is running [localhost:5001](http://localhost:5001/)

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
11:22:04.157 [info] module=Deployex.Deployment function=run_check/1 pid=<0.229.0>  Update is needed from 0.1.0 to 0.1.1.
11:22:04.381 [warning] module=Deployex.Upgrade function=check/3 pid=<0.229.0>  HOT UPGRADE version NOT DETECTED, full deployment required, result: []
11:22:04.381 [info] module=Deployex.Monitor function=handle_call/3 pid=<0.230.0>  Requested to stop application pid: #PID<0.231.0>
11:22:04.437 [warning] module=Deployex.Monitor function=handle_info/2 pid=<0.230.0>  Application with pid: #PID<0.231.0> - state: %{current_pid: nil} being stopped by reason: :normal
11:22:04.947 [info] module=Deployex.Monitor function=start_service/2 pid=<0.230.0>  Ensure running requested for version: 0.1.1
11:22:04.948 [info] module=Deployex.Monitor function=start_service/2 pid=<0.230.0>   - Starting /tmp/deployex/varlib/service/myphoenixapp/current/bin/myphoenixapp...
11:22:04.950 [info] module=Deployex.Monitor function=start_service/2 pid=<0.230.0>   - Running, monitoring pid = #PID<0.249.0>, OS process id = 9289.
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

*__ATTENTION: Be sure to have set the cookie in deployex, otherwise the hot-upgrade will fail and a full update will be performed.__*

```bash
14:18:20.329 [info] module=Deployex.Deployment function=run_check/1 pid=<0.235.0>  Update is needed from 0.1.1 to 0.1.2.
14:18:20.583 [warning] module=Deployex.Upgrade function=check/3 pid=<0.235.0>  HOT UPGRADE version DETECTED, from: 0.1.1 to: 0.1.2
14:18:20.815 [info] module=Deployex.Upgrade function=unpack_release/2 pid=<0.235.0>  Unpacked successfully: ~c"0.1.2"
14:18:20.925 [info] module=Deployex.Upgrade function=install_release/2 pid=<0.235.0>  Installed Release: ~c"0.1.2"
14:18:20.926 [info] module=Deployex.Upgrade function=permfy/2 pid=<0.235.0>  Made release permanent: 0.1.2
14:18:20.927 [info] module=Deployex.Upgrade function=run/2 pid=<0.235.0>  Release upgrade executed with success from 0.1.1 to 0.1.2
```

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
After making these changes, remove any previous `myphoenixapp` releases that do not support `mTLS` and proceed with deployment tests, including hot upgrades.

*__ATTENTION: Ensure that the cookie is properly set__*

## Throubleshooting

### Accessing monitored app logs

```bash
export monitored_app_name=myphoenixapp
# production
tail -f /var/log/${monitored_app_name}-stdout.log 
# local test
tail -f /tmp/${monitored_app_name}/${monitored_app_name}-stdout.log
```

### Connecting to the monitored app CLI

```bash
export monitored_app_name=myphoenixapp
# production
/var/lib/deployex/service/${monitored_app_name}/current/bin/${monitored_app_name} remote
# local test
/tmp/deployex/varlib/service/${monitored_app_name}/current/bin/${monitored_app_name} remote
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
4. *__Delete the Old Service Folder:__*
 The `old` service folder, containing the previous version of the application, is deleted to make space for the new version.
5. *__Move the Current Service:__*
 The `current` service folder, representing the current version of the application, is moved to the `old` service folder. Simultaneously, the `new` service folder is moved to become the new `current` service folder.
6. *__Start the Application:__*
 Finally, the application is started using the version now residing in the `current` service folder, ensuring that the latest version is active and operational.

By following this process, Deployex facilitates deployments, ensuring that applications are updated while minimizing downtime.

For the test environment:
```bash
/tmp/deployex/varlib/service/{monitored_app}/old/{monitored_app}
/tmp/deployex/varlib/service/{monitored_app}/new/{monitored_app}
/tmp/deployex/varlib/service/{monitored_app}/current/{monitored_app}
```

For production environment:
```bash
/var/lib/deployex/service/{monitored_app}/old/{monitored_app}
/var/lib/deployex/service/{monitored_app}/new/{monitored_app}
/var/lib/deployex/service/{monitored_app}/current/{monitored_app}
```

### Hot-upgrades

For this scenario, there will be no moving files/folders since the target is to keep the current service folder updated. The sequence is:

1. *__Download and Unpack the New Version:__*
 The new version of the application is downloaded and unpacked into the `new` service folder, ready for deployment.
2. *__Check if the release contain a hot-upgrade or full deployment:__*
 Deployex will check the release file received and if it is a hot-upgrade, goes to the step 3 .
3. *__Execute the Hotupgrade checks and verification__*
 Deployex will try to run the hotupgrade sequence and if succeeds, it makes the changes permanent. Inc ase of failure, it tries to execute a full deployment with the same release file.


