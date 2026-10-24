# Agent API

DeployEx can serve a JSON API and an event stream on a port of its own. Scripts, CI pipelines and other tools use it to read
the state of the host and the logs of its apps without the dashboard, and to restart an app, clear its ghosted versions or set
its mode. It is off by default.

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
gets. The logs are what the apps write to stdout and stderr, so a `read` token sees all that an app logs.

## HTTP

Send the token in the `Authorization` header:

```bash
curl -H "Authorization: Bearer $TOKEN" http://10.0.1.12:5002/v1/apps/myphoenixapp
```

| Path | Returns |
|---|---|
| `GET /v1/node` | DeployEx: the node, version, `started_at` (the start of its VM), OTP and Elixir versions. The host: the OS, `uptime_seconds`, CPU and memory |
| `GET /v1/apps` | Every monitored app, as below |
| `GET /v1/apps/:name` | One monitored app: its mode, its ghosted versions and its instances |
| `GET /v1/apps/:name/versions` | The version history of the app |
| `GET /v1/apps/:name/ghosted` | The ghosted versions of the app |
| `GET /v1/apps/:name/logs` | The stdout or stderr lines of one instance of the app (see [Logs](#logs)) |

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
      "started_at": "2026-10-23T09:12:45Z",
      "ports": [{"key": "PORT", "port": 4000}]
    }
  ]
}
```

Times are UTC, in ISO 8601. `started_at` is when the instance last started, and it is `null` for an instance that did not start.

| Status | When |
|---|---|
| `401` | No token, or a token that is not in `DEPLOYEX_API_TOKENS` |
| `403` | The token does not have the scope of the path |
| `404` | The host does not monitor the app, or the path does not exist |
| `503` | DeployEx did not answer, for example while it starts |

## Operate

A token with the `operate` scope can do what the dashboard buttons do. Each call first checks that the host monitors the app
named in the path. The restart is the Full Restart: the monitored app is down until its first instance is back.

| Call | Does | Returns |
|---|---|---|
| `POST /v1/apps/:name/restart` | Stops every instance at once and deploys each again, as Full Restart | `202`. It runs after the reply |
| `DELETE /v1/apps/:name/ghosted/:version` | Removes one ghosted version | `200` with the rest. `404` if it is not ghosted |
| `POST /v1/apps/:name/ghosted/clear` | Clears the ghosted versions | `200` with an empty list |
| `PUT /v1/apps/:name/mode` | Sets the mode | `200`. `422` for an unknown mode or a version not in the history. `400` for bad JSON |

The mode call takes a JSON body, `{"mode": "automatic"}` or `{"mode": "manual", "version": "1.4.1"}`:

```bash
curl -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"mode": "manual", "version": "1.4.1"}' http://10.0.1.12:5002/v1/apps/myphoenixapp/mode
```

`GET /v1/apps/:name` shows a new mode within about one second, at the next status refresh. A `503` from the mode call can still
set the mode later, so read `GET /v1/apps/:name` before a retry.

Each operate call with a known token writes one audit line to the DeployEx log, also when DeployEx refuses the call
(`404`, `422`, `503`) or the token has no `operate` scope:

```text
Agent API operate: token=ops from=10.0.1.20 action=set_mode app="myphoenixapp" mode="manual" version="1.4.1" result=ok
Agent API operate: token=ci from=10.0.1.20 action="POST /v1/apps/myphoenixapp/restart" result=forbidden
```

A call with the `operate` scope that DeployEx cannot read gets no audit line: `400` for a body that is not JSON, `413` for
a body over 4 KB, and `406` for an `Accept` header without JSON.

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
| `logs:<sname>:<type>` | `logs` with the new lines of one instance, in the body of `GET /v1/apps/:name/logs` (see [Logs](#logs)) |

The `apps` topic also pushes `app_removed`, with the `name` of an app that the host no longer monitors. The events have the
names and payloads that the `Foundation.Notifications` module documents. The `events` topic sends only the events
of this host, also when DeployEx nodes are connected.

## Logs

DeployEx keeps the stdout and stderr lines of each instance in memory for `logs_retention_time_ms` (1 hour by default). A
restart of DeployEx clears them. A `read` token gets them by the `sname` of the instance and the log type:

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "http://10.0.1.12:5002/v1/apps/myphoenixapp/logs?sname=myphoenixapp-kxp3wq&type=stdout&since=2026-10-23T09:12:00Z"
```

```json
{
  "logs": [
    {"timestamp": "2026-10-23T09:12:45.120Z", "line": "09:12:45.118 [info] Running MyphoenixappWeb.Endpoint with Bandit"},
    {"timestamp": "2026-10-23T09:12:45.120Z", "line": "09:12:45.119 [info] Access MyphoenixappWeb.Endpoint at http://localhost:4000"}
  ]
}
```

| Parameter | Value |
|---|---|
| `sname` | Required. An instance in `GET /v1/apps/:name`, or an old one: each version in `/versions` and `/ghosted` has its `sname` |
| `type` | Required. `stdout` or `stderr` |
| `since` | Optional. An ISO 8601 time with an offset. Returns the lines at or after it. Without it, all lines that DeployEx keeps |

The lines come oldest first. `timestamp` is the time DeployEx read the line, to the millisecond. A long line that `tail` sends
in two parts comes as two entries. In a URL, write the `+` of an offset as `%2B`, or use `Z`. To poll, send the last
`timestamp` as `since` on each call, and drop the lines with that time that you already have.

| Status | When |
|---|---|
| `404` | The `sname` is not an instance of the app, or DeployEx keeps no logs for it |
| `422` | No `sname`, a `type` that is not `stdout` or `stderr`, or a `since` that is not ISO 8601 with an offset |

The `logs:<sname>:<type>` topic pushes `logs` with each new group of lines:

```js
const channel = socket.channel("logs:myphoenixapp-kxp3wq:stderr")
channel.on("logs", ({logs}) => logs.forEach(({timestamp, line}) => console.log(timestamp, line)))
channel.join()
```

The join fails with `not_found` for an `sname` or a `type` that the `GET` refuses with `404` or `422`, with `forbidden` for a
token without `read`, and with `unavailable` before the first status update, so join again later. To miss no line, join the
topic before the `GET`, and drop the lines that come in both.

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
