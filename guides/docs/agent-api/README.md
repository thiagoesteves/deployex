# Agent API

DeployEx can serve a JSON API and an event stream on a port of its own. Scripts, CI pipelines and other tools use it to read
the state of the host without the dashboard, and to restart an app, clear its ghosted versions or set its mode. It is off by
default.

## Turn it on

1. Make a token and its entry:

   ```bash
   TOKEN=$(openssl rand -hex 32)
   echo "ci:read:$(printf %s "$TOKEN" | sha256sum | cut -d' ' -f1)"
   ```

   Give the token to the client. DeployEx keeps only the SHA-256 hash.

2. Put the entry in the `DEPLOYEX_API_TOKENS` secret, next to `DEPLOYEX_SECRET_KEY_BASE` (aws, gcp or env secrets adapter).
   Separate the entries with commas:

   ```text
   ci:read:9f86d081...,ops:read+operate:2c26b46b...
   ```

   Each entry is `name:scopes:sha256`. Join the scopes with `+`. The scopes are `read` and `operate` (see [Operate](#operate)).
   `operate` does not include `read`, so a token that reads and operates lists `read+operate`. DeployEx ignores an entry that
   it cannot parse, and logs its position, not its value.

3. Turn the listener on in the YAML file:

   ```yaml
   agent_api:
     enabled: true                                        # Optional, default: false
     port: 5002                                           # Optional, default: 5002
   ```

   To serve only HTTPS, add a certificate and its key. Both files must exist when DeployEx starts, or the boot stops with
   `agent_api certfile <path> not found`:

   ```yaml
     certfile: "/etc/deployex/api.crt"
     keyfile: "/etc/deployex/api.key"
   ```

4. Restart DeployEx. It reads the section and the secret when it starts.

To rotate a token, add the new entry, move the client to the new token, then remove the old entry. Restart DeployEx after
each change of the secret.

Keep the port off public load balancers. Allow it only from the hosts that call it, for example with a security group rule.
Set `certfile` and `keyfile` when the traffic leaves the private network. The HTTP resources and the `apps` topic never
return the app env, a secret or the pre_commands of a version. The `events` topic sends the payloads that the webhook adapter
gets.

## HTTP

Send the token in the `Authorization` header:

```bash
curl -H "Authorization: Bearer $TOKEN" http://10.0.1.12:5002/v1/apps/myphoenixapp
```

| Path | Returns |
|---|---|
| `GET /v1/node` | DeployEx: the node, version, uptime, OTP and Elixir versions. The host: the OS, uptime, CPU and memory |
| `GET /v1/apps` | Every monitored app, as below |
| `GET /v1/apps/:name` | One monitored app: its mode, its ghosted versions and its instances |
| `GET /v1/apps/:name/versions` | The version history of the app |
| `GET /v1/apps/:name/ghosted` | The ghosted versions of the app |

```json
{
  "name": "myphoenixapp",
  "language": "elixir",
  "replicas": 2,
  "mode": "automatic",
  "manual_version": null,
  "ghosted_versions": ["1.4.1"],
  "instances": [
    {
      "sname": "myphoenixapp-kxp3wq",
      "node": "myphoenixapp-kxp3wq@ip-10-0-1-12",
      "version": "1.4.2",
      "status": "running",
      "otp": "connected",
      "last_deployment": "hot_upgrade",
      "crash_restart_count": 0,
      "force_restart_count": 0,
      "uptime": "3h ago",
      "ports": [{"key": "PORT", "port": 4000}]
    }
  ]
}
```

| Status | When |
|---|---|
| `401` | No token, or a token that is not in `DEPLOYEX_API_TOKENS` |
| `403` | The token does not have the scope of the path |
| `404` | The host does not monitor the app, or the path does not exist |
| `503` | DeployEx did not answer, for example while it starts |

## Operate

A token with the `operate` scope can do what the dashboard buttons do. Each call first checks that the host monitors the app.

| Call | Does | Returns |
|---|---|---|
| `POST /v1/apps/:name/restart` | Restarts every instance of the app, as the restart button does | `202`. It restarts after the reply |
| `DELETE /v1/apps/:name/ghosted/:version` | Removes one ghosted version | `200` with the rest. `404` if it is not ghosted |
| `DELETE /v1/apps/:name/ghosted` | Clears the ghosted versions | `200` with an empty list |
| `PUT /v1/apps/:name/mode` | Sets the mode | `200` with the mode. `422` for an unknown mode or a version not in the history |

The mode call takes a JSON body, `{"mode": "automatic"}` or `{"mode": "manual", "version": "1.4.1"}`:

```bash
curl -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"mode": "manual", "version": "1.4.1"}' http://10.0.1.12:5002/v1/apps/myphoenixapp/mode
```

`GET /v1/apps/:name` shows a new mode within about one second, at the next status refresh.

Each operate call writes one audit line to the DeployEx log, also when it fails or the token has no `operate` scope:

```text
Agent API operate: token=ops from=10.0.1.20 action=set_mode app="myphoenixapp" mode="manual" version="1.4.1" result=ok
Agent API operate: token=ci from=10.0.1.20 action="POST /v1/apps/myphoenixapp/restart" result=forbidden
```

## Event stream

The socket is a Phoenix Channels socket at `/v1/socket`. Send the token as the Phoenix `authToken`, never in the URL:

```js
import {Socket} from "phoenix"

const socket = new Socket("ws://10.0.1.12:5002/v1/socket", {authToken: token})
socket.connect()

const channel = socket.channel("events")
channel.on("event", ({event, payload}) => console.log(event, payload))
channel.join()
```

The socket refuses a browser page from another site, so run the client outside a browser, for example in Node or a CI job.

A client without the Phoenix JavaScript library sends the token in the `Sec-WebSocket-Protocol` header of the upgrade, as
`phoenix, base64url.bearer.phx.<the token in base64, without padding>`, and connects to `/v1/socket/websocket?vsn=2.0.0`.
It sends a `heartbeat` on the `phoenix` topic at least every 60 seconds, or DeployEx closes the socket.

| Topic | Pushes |
|---|---|
| `events` | `event` for each notification event, with the body that the webhook adapter posts: `event`, `timestamp`, `payload` |
| `apps` | The join reply has `apps`, every app as in `GET /v1/apps`. Then `app` each time one app changes |

The `apps` topic also pushes `app_removed`, with the `name` of an app that the host no longer monitors. The events have the
names and payloads that the `Foundation.Notifications` module documents. The `events` topic sends only the events
of this host, also when DeployEx nodes are connected.

## Check a rollout from a pipeline

After the pipeline writes a new `current.json`, it can ask each host whether the version runs or is ghosted:

```bash
app=$(curl -sf -H "Authorization: Bearer $TOKEN" "http://$HOST:5002/v1/apps/myphoenixapp")
echo "$app" | jq -e --arg v "$VERSION" \
  '(.instances | length) == .replicas and all(.instances[]; .version == $v and .status == "running")' && echo "running"
echo "$app" | jq -e --arg v "$VERSION" '.ghosted_versions | index($v) != null' && echo "ghosted"
```

When the version is ghosted, the pipeline writes the previous version back to `current.json`.

## Local run

Export the tokens before you start DeployEx. The listener then serves `http://localhost:5002`:

```bash
export DEPLOYEX_API_TOKENS="dev:read:$(printf %s "$TOKEN" | shasum -a 256 | cut -d' ' -f1)"
make start
```
