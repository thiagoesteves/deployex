# GCP Deployment (with terraform)

This is an example of how to install deployex in a GCP cloud using terraform to programatically setup the enviromnent.

## Setup

To begin, ensure the following applications are installed:

 * Terraform
 * [Google Cloud SDK](https://cloud.google.com/sdk/docs/install-sdk?hl=pt-br)

### 1. Create a Project in GCP and populate the terraform variables

Using the GCP interface:
 * [Create a project](https://developers.google.com/workspace/guides/create-project?hl=pt-br#google-cloud-console), e. g. `deployex`
 * [Create a service account](https://console.cloud.google.com/iam-admin/serviceaccounts?project=deployex-435117&supportedpurview=project) and generate keys. The JSON file with the keys will be downloaded to your local machine. In this example, the file was saved with the name `deployex-gcp-terraform.json`.
 * Retrieve access token using [google cloud terminal](https://shell.cloud.google.com/?pli=1&show=ide%2Cterminal) and the command `gcloud beta auth application-default print-access-token`
 * Enable the following resources: VM instances, Secret Manager

### 2. Environment Secrets

Ensure you have access to the following secrets for storage in AWS Secrets Manager:

 - DEPLOYEX_SECRET_KEY_BASE
 - DEPLOYEX_ERLANG_COOKIE
 - DEPLOYEX_ADMIN_HASHED_PASSWORD
 - MYAPPNAME_SECRET_KEY_BASE
 - MYAPPNAME_ERLANG_COOKIE

### 3. Variables Configuration

Rename the file [main_example.tf_](./environments/prod/main_example.tf_) to [main.tf](./environments/prod/main.tf) and verify and set the variables according to the specific environment including the [variables file](./modules/standard-account/variables.tf). These variables will be used in all terraform templates to set-up correctly.

### 4. Provisioning the Environment

Once the key is configured, proceed with provisioning the environment. Navigate to the `./environments/prod` folder and execute the following commands:

```bash
terraform plan # Check if the templates are configured correctly
terraform apply # Apply the configurations to create the environment
```

__PS__: At this point, you may face some issues if the billing is not set properly or the resource is not enabled. The token expires after a time, so you may need to renew it.

Wait for the environment to be created. Once it is created, you can check the instance at this [address](https://console.cloud.google.com/compute/instances). Afterward, update the variables in the *__myappname-prod-secrets__* secret in the [GCP Secrets Manager](https://console.cloud.google.com/security/secret-manager). You will need to add a new version and update the secret with Jason format.

```bash
{"MYAPPNAME_SECRET_KEY_BASE":"xxxxxxxxxx","MYAPPNAME_ERLANG_COOKIE":"xxxxxxxxxx"}
```

Additionally, create the TLS certificates for the OTP distribution using the [Following script](../../../devops/scripts/tls-distribution-certs), changing the appropriate names and regions inside it.

```bash
make tls-distribution-certs
```

Add the following certificates as plain text for each of the following secrets:
 - *__myappname-stage-otp-tls-ca__*
 - *__myappname-stage-otp-tls-key__*
 - *__myappname-stage-otp-tls-crt__*

Add the Deployex secrets, which should be added in the *__deployex-myappname-prod-secrets__*  with the corresponding values.

 ```bash
{"MYAPPNAME_SECRET_KEY_BASE":"xxxxxxxxxx","MYAPPNAME_ERLANG_COOKIE":"xxxxxxxxxx","DEPLOYEX_ADMIN_HASHED_PASSWORD":"xxxxxxxxxx"}
```

*__PS__*: __DEPLOYEX_ERLANG_COOKIE__ and __MYAPPNAME_ERLANG_COOKIE__ __MUST__ match because they will be used by the OTP distribution.

### 5. EC2 Provisioning (Manual Steps)

When running Terraform for the first time, AWS secrets are not yet created. Consequently, attempts to execute deployex or certificates installation will fail. Once these secrets, including certificates and other sensitive information, are updated, subsequent iterations of Terraform's Instance destroy/create process will no longer require manual intervention.

For initial installations or updates to deployex, access the Google Compute Instance via ssh using the dashboard and after getting access to GCI, you need to grant root permissions:

```bash
my-user@myfirstapp-prod-instance:~$ sudo su
root@myfirstapp-prod-instance:/home/my-user# cd ../ubuntu/
root@myfirstapp-prod-instance:/home/ubuntu# ls
```

Authenticate using the CLI:
```bash
root@myfirstapp-prod-instance:/home/ubuntu# gcloud auth login
```

Copy the link passed and paste in your browser, capture the verification and paste it in the terminal.

```bash
You are now logged in as [my-user@gmail.com].
Your current project is [deployex-123456].  You can change this setting by running:
  $ gcloud config set project PROJECT_ID
```

Since the secrets are already updated, we are going to install them in the appropriate addresses
```bash
./install-otp-certificates.sh 

# Installing Certificates env: stage at /usr/local/share/ca-certificates #
Retrieving and saving ......
[OK]
```

you can check if the certificates were installed correctly:

```bash
ls /usr/local/share/ca-certificates
ca.crt  myappname.crt myappname.key deployex.crt  deployex.key
```

Run the script to install (or update) deployex:

```bash
root@ip-10-0-1-116:/home/ubuntu# ./deployex.sh --install deployex-config.json
#           Removing Deployex              #
...
# Clean and create a new directory         #
# Start systemd                            #
# Start new service                        #
Created symlink /etc/systemd/system/multi-user.target.wants/deployex.service → /etc/systemd/system/deployex.service.
root@ip-10-0-1-116:/home/ubuntu#
```

If the deployex needs to be updated, open the file `deployex-config.json` and update to the new version:

```bash
vi deployex-config.json
{
 ...
  "version": "0.3.0-rc15",
  "os_target": "ubuntu-20.04",
  ...
```

Once the file is updated, run the update command:
```bash
root@ip-10-0-1-116:/home/ubuntu# ./deployex.sh --update deployex-config.json
```

If deployex is running and still there is no version of the monitored app available, you should see this message in the logs:
```bash
tail -f /var/log/deployex/deployex-stdout.log
or
tail -f /var/log/deployex/deployex-stderr.log
```

### 6. Monitored App deployment

Once deployex is running, the monitored app __MUST__ then be deployed, creating the release package and the json file in the appropriate storage. The final `current.json` file should be similar to:

```bash
{
  "version": "0.1.0-9cad9cd",
  "hash": "9cad9cd3581c69fdd02ff60765e1c7dd4599d84a",
  "pre_commands": []
}
```

Tracking the `mix.exs` version is essential to allow hot-upgrades.