# AWS Hosts With No Internet Route

This guide runs DeployEx on an AWS host in a private subnet that has no NAT gateway and no internet gateway route. The host
reaches AWS only through VPC endpoints.

A pipeline downloads each DeployEx release from GitHub, scans it, and uploads it to a private S3 bucket. The hosts install and
upgrade DeployEx only from that bucket, so they run only a release that passed the scan.

## What needs the internet

| Feature | On a host with no internet route |
|---|---|
| Monitored app releases (`release_adapter: "s3"`) | Work through the S3 gateway endpoint |
| DeployEx releases: install, update, hot upgrade, self-upgrade | Read from an `s3://` base, see below |
| GitHub release check (the update notice on the dashboard) | Set `enable_release_check: false` |
| Secrets (`secrets_adapter: "aws"`) | Work through the Secrets Manager interface endpoint |
| OS packages | Come from the host image, see [Host image](#5-host-image) |

These opt-in features need the internet and do not work. Leave them off: Let's Encrypt and Cloudflare certificates, GitHub SSO
(`auth`), Slack, PagerDuty, webhooks to an internet address, and the hot upgrade from a GitHub artifact.

## 1. Bucket layout

Put each version under its own prefix, with the files of the GitHub release that the hosts use:

```
s3://my-deployex-releases/deployex/0.10.1/checksum.txt
s3://my-deployex-releases/deployex/0.10.1/deployex.sh
s3://my-deployex-releases/deployex/0.10.1/deployex-ubuntu-24.04-otp-28.tar.gz
```

The tarball name is `deployex-<os_target>-otp-<otp_version>.tar.gz`, from the DeployEx YAML. An arm64 host takes
`deployex-<os_target>-arm64-otp-<otp_version>.tar.gz`. Upload `checksum.txt` as it is:
the installer checks the tarball against it, and cloud-init checks `deployex.sh` against it.

A pipeline step that downloads, scans and uploads a version:

```bash
set -euo pipefail
VERSION=0.10.1
mkdir -p "release/${VERSION}" && cd "release/${VERSION}"
gh release download "${VERSION}" -R thiagoesteves/deployex \
  -p checksum.txt -p deployex.sh -p "deployex-ubuntu-24.04*-otp-28.tar.gz"
sha256sum --check --ignore-missing checksum.txt
# Scan the files here, and stop if the scan fails.
aws s3 cp . "s3://my-deployex-releases/deployex/${VERSION}/" --recursive
```

## 2. IAM

The instance role reads the releases with `s3:GetObject` on the prefix. The bucket stays private, and the host needs no static
keys:

```json
{
  "Effect": "Allow",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::my-deployex-releases/deployex/*"
}
```

With only `s3:GetObject`, S3 answers `403 Forbidden` for a key that does not exist, the same as for a denied read. Also allow
`s3:ListBucket` on `arn:aws:s3:::my-deployex-releases` to get `404 Not Found` for a missing version.

If the bucket uses SSE-KMS with a customer managed key, the role also needs `kms:Decrypt` on that key.

## 3. VPC endpoints

| Endpoint | Type | When |
|---|---|---|
| `com.amazonaws.<region>.s3` | Gateway, on the route table of the private subnet | Always. The bucket must be in the same region |
| `com.amazonaws.<region>.secretsmanager` | Interface, private DNS on | `secrets_adapter: "aws"`, or cloud-init reads secrets |
| `com.amazonaws.<region>.ssm`, `ssmmessages`, `ec2messages` | Interface, private DNS on | Session Manager access to the host |
| `com.amazonaws.<region>.logs` | Interface, private DNS on | The CloudWatch agent sends the logs |

An interface endpoint needs a security group that allows HTTPS (port 443) from the private subnet. The installer reads the
bucket in the region set by `aws_region` in the DeployEx YAML, so set it.

## 4. DeployEx settings

```yaml
aws_region: "us-east-2"
enable_release_check: false
self_upgrade:
  enabled: true
  source: "aws"
  dist_base_url: "s3://my-deployex-releases/deployex"  # DeployEx adds /{version}
```

DeployEx reads `enable_release_check` at boot. After a hot upgrade into the first version that has the key, it applies after
the next restart.

## 5. Host image

`apt` cannot reach a mirror, and the downloads in the `runcmd` of the other AWS guides fail. Build the host image with:

- the packages in the cloud-init `packages` list, including the AWS CLI and `yq`
- the CloudWatch agent, which the other guides download from `s3.amazonaws.com`
- the RDS CA bundle, if the monitored app uses it, which the other guides download from `truststore.pki.rds.amazonaws.com`

Then remove the `packages` list and these downloads from cloud-init. A download with no route can wait many minutes before it
fails. The installer reads an `s3://` base with `aws s3 cp`, and stops with an error if the AWS CLI is not on the host.

Also remove the certbot step (`setup-tls.sh`), because Let's Encrypt cannot reach the host. End TLS at a load balancer
instead, and change two servers in the nginx config of the other guides:

- The port 80 server for the host names redirects every request to HTTPS, which loops behind a load balancer. Replace it
  with one port 80 server per host name, which proxies to the monitored app or to DeployEx, as their port 443 servers do.
- The port 80 default server (`server_name _`) answers 404. The load balancer health check uses the instance IP as the host
  name, so it reaches this server. Make it proxy to DeployEx, and set the health check path to `/health`, which answers 200.

## 6. Install the first version from the bucket

In cloud-init, take `deployex.sh` and `checksum.txt` from the bucket, check the installer, and install. `DX_VERSION` is the
version to install. The AWS-Elixir, AWS-Erlang and AWS-Gleam guides read it from the `deployex_version` instance tag and
write it into the YAML with `sed`. Keep both steps. The AWS-Elixir-DB-CertManager guide renders the version into its
template, so there set `DX_VERSION="${deployex_version}"` first. Then, in place of their `wget` of `deployex.sh` and their
`--install` line:

```bash
BASE="s3://my-deployex-releases/deployex"
cd /home/root
aws s3 cp --region us-east-2 "$BASE/$DX_VERSION/deployex.sh" deployex.sh &&
  aws s3 cp --region us-east-2 "$BASE/$DX_VERSION/checksum.txt" checksum.txt &&
  grep ' deployex.sh$' checksum.txt | sha256sum --check ||
  { echo "cannot get or check deployex.sh $DX_VERSION, DeployEx not installed" >&2; exit 1; }
chmod a+x deployex.sh
./deployex.sh --install /home/root/deployex.yaml --dist "$BASE/{version}"
```

The variables have no braces, so the snippet also works in their Terraform templates, where `${...}` is a template variable.
There, the region can be `${aws_region}`.

All `runcmd` steps run as one script, so `exit 1` also stops the steps after it.

## 7. Upgrades

- Self-upgrade: upload the version to the bucket, then bump the `deployex_version` tag. DeployEx runs
  `deployex.sh --hot-upgrade` with `--dist s3://my-deployex-releases/deployex/{version}`.
- By hand: `./deployex.sh --update --dist 's3://my-deployex-releases/deployex/{version}'`, with the new `version` in the YAML.

If the tag names a version that is not in the bucket yet, the self-upgrade fails and does not try that version again. After the
upload, retry it as the [Hot Upgrades](../hot-upgrades/README.md#method-4-terraform-iac-self-upgrade) guide says.

The `deployex.sh` on the host must be one that reads `s3://`. A host installed from the bucket has it. On an older host,
replace it with the one of the new version first. `aws s3 cp` writes a new file without the exec bit, so set it again:

```bash
BASE="s3://my-deployex-releases/deployex/<version>"
cd /home/root
aws s3 cp --region us-east-2 "$BASE/deployex.sh" deployex.sh.new &&
  aws s3 cp --region us-east-2 "$BASE/checksum.txt" checksum.txt &&
  grep ' deployex.sh$' checksum.txt | sed 's/deployex.sh$/deployex.sh.new/' | sha256sum --check &&
  chmod a+x deployex.sh.new && mv deployex.sh.new deployex.sh
```

## Troubleshooting

A failed read logs `Error: cannot read <s3 URL>: <AWS CLI error>`, which names the S3 key and the reason. For a version that
is not in the bucket:

```
Error: cannot read s3://my-deployex-releases/deployex/0.10.2/checksum.txt: fatal error: An error occurred (403) when
calling the HeadObject operation: Forbidden
Error while trying to download checksum from: s3://my-deployex-releases/deployex/0.10.2
```

The first error is one line in the log.

- `403 Forbidden`: the role cannot read the key, or the key does not exist (see [IAM](#2-iam)).
- `(404) ... Key "deployex/0.10.2/checksum.txt" does not exist`: the version is not in the bucket. The role has
  `s3:ListBucket`.
- A connect timeout: the route table of the subnet has no S3 gateway endpoint, or `aws_region` is not the bucket region.
- `install the AWS CLI (aws) to read it`: the host image has no AWS CLI.
