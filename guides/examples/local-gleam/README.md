## 1. Running DeployEx and Monitored Gleam Application locally

For local testing, the root path used for distribution releases and versions is `/tmp/deployex/bucket`. Let's create the required release folders:
```bash
export monitored_app_name=mygleamapp
mkdir -p /tmp/deployex/bucket/dist/${monitored_app_name}
mkdir -p /tmp/deployex/bucket/versions/${monitored_app_name}/local/
```

It is important to note that for local deployments, DeployEx will use the path `/tmp/deployex/varlib` for local storage. This means you can delete the entire folder to reset any local version, history, or configurations.

## 2. Creating a Gleam app (default name is `mygleamapp`)

In this example, we create a brand new gleam app:

```bash
gleam new mygleamapp
cd mygleamapp
```

Add the following dependency (gleam_erlang) at `gleam.toml`:
```gleam
[dependencies]
gleam_stdlib = ">= 0.34.0 and < 2.0.0"
gleam_erlang = ">= 0.27.0 and < 1.0.0"
```

Modify the main function to sleep forever at `src/mygleamapp.gleam`, otherwise the application will run and exit:

```gleam
import gleam/io
import gleam/erlang/process

pub fn main() {
  io.println("Hello from mygleamapp!")
  process.sleep_forever()
}
```

## 3. Generate a release
Then you can compile and generate a release
```bash
gleam deps update
gleam export erlang-shipment
```

Pack the release and move it to the distributed folder and updated the version:
```bash
cd build
export app_name=mygleamapp
export release_path=erlang-shipment
tar -czvf ${release_path}/${app_name}-0.1.0.tar.gz ${release_path}
cp ${release_path}/${app_name}-0.1.0.tar.gz /tmp/deployex/bucket/dist/${app_name}
echo "{\"version\":\"0.1.0\",\"pre_commands\": [],\"hash\":\"local\"}" | jq > /tmp/deployex/bucket/versions/${app_name}/local/current.json
```

> [!NOTE]
> Gleam doesn't have a release command (yet). For DeployEx to operate properly, we need a tarball that contains the erlang-shipment
> with the respective version. There is an example in [cochito](https://github.com/chouzar/cochito/blob/main/.github/workflows/release.yml)

## 4. Running DeployEx and deploy the app

### Adding a Gleam Monitored Application

The default `dev` application for deployex is `myphoenixapp`. To add a Gleam application to monitoring, update the `config/dev.exs` file:

```elixir
config :foundation,
  env: "local",
  base_path: "/tmp/deployex/varlib",
  monitored_app_log_path: "/tmp/deployex/varlog",
  applications: [
    %{
      name: "mygleam",
      replicas: 2,
      language: "gleam",
      replica_ports: [%{key: "PORT", base: 4000}],
      env: []
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
[info] Update is needed at sname: mygleamapp-v636fq from: <no current set> to: 0.1.0
[warning] HOT UPGRADE version NOT DETECTED, full deployment required, reason: :not_found
[info] Full deploy instance: 1 sname: mygleamapp-ud48pz
[info] Initializing monitor server for sname: mygleamapp-ud48pz language: elixir
[info] Ensure running requested for sname: mygleamapp-ud48pz version: 0.1.0
[info]  # Identified executable: /tmp/deployex/varlib/service/mygleamapp/mygleamapp-ud48pz/current/bin/mygleamapp
[info]  # Starting application
[info]  # Running sname: mygleamapp-ud48pz, monitoring pid = #PID<0.3037.0>, OS process = 6479 sname: mygleamapp-ud48pz
[info]  # Application sname: mygleamapp-ud48pz is running
[info]  # Moving to the next instance: 2
...
iex(deployex@hostname)1>
```

You should then visit the application and check it is running [localhost:5001](http://localhost:5001/). Since you are not using mTLS, the dashboard should look like this:

![No mTLS Dashboard Gleam](../../static/deployex_monitoring_app_gleam_no_tls.png)

Note that the __OTP-Nodes are connected__, but the __mTLS is not supported__. The __mTLS__ can be enabled and it will be covered ahead. Leave this terminal running and open a new one to compile and release the monitored app.

## 5. Updating the application

### Full deployment

In this scenario, the existing application will undergo termination, paving the way for the deployment of the new one. It's crucial to maintain the continuous operation of DeployEx throughout this process. Navigate to the `mygleamapp` project and increment the version in the `gleam.toml` file.

1. Remove any previously generated files and generate a new release
```bash
gleam export erlang-shipment
```

2. Now, *__keep DeployEx running in another terminal__* and copy the release file to the distribution folder and proceed to update the version accordingly:
```bash
export app_name=mygleamapp
export release_path=erlang-shipment
cd build
tar -czvf ${release_path}/${app_name}-0.1.1.tar.gz ${release_path}
cp ${release_path}/${app_name}-0.1.1.tar.gz /tmp/deployex/bucket/dist/${app_name}
echo "{\"version\":\"0.1.1\",\"pre_commands\": [],\"hash\":\"local\"}" | jq > /tmp/deployex/bucket/versions/${app_name}/local/current.json
```

3. You should then see the following messages in the DeployEx terminal while updating the app:
```bash
[info] Update is needed at sname: mygleamapp-ud48pz from: 0.1.0 to: 0.1.1
[warning] HOT UPGRADE version NOT DETECTED, full deployment required, reason: :not_found
[info] Full deploy instance: 1 sname: mygleamapp-1j535g
[info] Requested sname: mygleamapp-ipzc1l to stop application pid: #PID<0.1392.0>
[warning] Remaining beam app removed for sname: mygleamapp-ipzc1l
[info] Initializing monitor server for sname: mygleamapp-1j535g language: elixir
[info] Ensure running requested for sname: mygleamapp-1j535g version: 0.1.1
[info]  # Identified executable: /tmp/deployex/varlib/service/mygleamapp/mygleamapp-1j535g/current/bin/mygleamapp
[info]  # Starting application
[info]  # Running sname: mygleamapp-1j535g, monitoring pid = #PID<0.3423.0>, OS process = 6967 sname: mygleamapp-1j535g
[info]  # Application sname: mygleamapp-1j535g is running
[info]  # Moving to the next instance: 2
...
```

## 6. 🔑 Enhancing OTP Distribution Security with mTLS

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

4. To enable `mTLS` for DeployEx, set the appropriate Erlang options before running the application in the terminal:
```bash
ELIXIR_ERL_OPTIONS="-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf -setcookie cookie" iex --sname deployex -S mix phx.server
```

After making these changes, create and publish a new version `0.1.2` for `mygleamapp` and run the DeployEx with the command from item 5. After the deployment, you should see the following dashboard:

![mTLS Dashboard Gleam](../../static/deployex_monitoring_app_gleam_tls.png)