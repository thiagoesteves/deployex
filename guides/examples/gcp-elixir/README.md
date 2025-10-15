# GCP Deployment for Elixir with Terraform

This guide demonstrates how to deploy DeployEx in Google Cloud Platform (GCP) using Terraform to programmatically set up the environment.

## 1. Requirements

To begin, ensure the following applications are installed:

 * Terraform
 * [Google Cloud SDK](https://cloud.google.com/sdk/docs/install-sdk?hl=pt-br)

## 2. Create a Project in GCP and populate the terraform variables

Using the Google Cloud Dashboard:
 * [Create a project](https://developers.google.com/workspace/guides/create-project), e. g.,`deployex`
 * [Create a service account](https://console.cloud.google.com/iam-admin/serviceaccounts) and generate keys. The JSON file with the keys will be downloaded to your local machine. In this example, save the file as `deployex-gcp-terraform.json`.
 * Retrieve access token using the [google cloud terminal](https://shell.cloud.google.com/?pli=1&show=ide%2Cterminal) and the command: `gcloud beta auth application-default print-access-token`
 * Enable the following resources in GCP: Google Compute Engine (GCE) and Secret Manager.

## 3. Environment Secrets

Ensure you have access to the following secrets for storage in Secrets Manager:

| SECRET NAME | EXAMPLE | SOURCE |
|----------|-------------|------:|
| DEPLOYEX_SECRET_KEY_BASE | 42otsNl...Fpq3dIJ02 | mix phx.gen.secret |
| DEPLOYEX_ERLANG_COOKIE| my-cookie |  |
| DEPLOYEX_ADMIN_HASHED_PASSWORD | $2b$12$...3Lu6ys538TW | Bcrypt.hash_pwd_salt("my-pass") |
| MYAPPNAME_SECRET_KEY_BASE | 42otsNl...Fpq3dIJ02 | mix phx.gen.secret |
| MYAPPNAME_ERLANG_COOKIE | my-cookie |  |

> [!ATTENTION]
> The ENV vars `DEPLOYEX_CONFIG_YAML_PATH` and `DEPLOYEX_OTP_TLS_CERT_PATH` will be set automatically by the script `deployex.sh`.

## 4. Variables Configuration

Rename the file [main\_example.tf\_][main] to `main.tf` and verify and configure the variables according to your specific environment. Ensure that you also review and update the [variables file][var]. These variables will be utilized across all Terraform templates to ensure correct setup.

## 5. Provisioning the Environment

### Creating the Environment

Once the variables are configured, proceed with provisioning the environment. Navigate to the `./environments/prod` folder and execute the following commands:

```bash
terraform plan # Check if the templates are configured correctly
terraform apply # Apply the configurations to create the environment
```

> [!IMPORTANT]
> At this stage, you might encounter issues if billing is not properly set up or if required resources are not enabled. Additionally, the access token may expire over time, so you might need to renew it.

Wait for the environment to be created. Once the provisioning is complete, you can check the instance at this [address](https://console.cloud.google.com/compute/instances).

### Updating Secret Manager

Navigate to [GCP Secrets Manager](https://console.cloud.google.com/security/secret-manager), locate and update the following secrets:

 *  *__myappname-prod-secrets__*:

Create a new version of the secret and add the following JSON structure as plain text (You may need to configure additional secrets if your application requires them):
```bash
{"MYAPPNAME_SECRET_KEY_BASE":"xxxxxxxxxx","MYAPPNAME_ERLANG_COOKIE":"xxxxxxxxxx"}
```

* *__deployex-myappname-prod-secrets__*

Create a new version of the secret and add the following JSON structure as plain text:
 ```bash
{"DEPLOYEX_SECRET_KEY_BASE":"xxxxxxxxxx","DEPLOYEX_ERLANG_COOKIE":"xxxxxxxxxx","DEPLOYEX_ADMIN_HASHED_PASSWORD":"xxxxxxxxxx"}
```

 *  *__myappname-stage-otp-tls-ca__*, *__myappname-stage-otp-tls-key__*, *__myappname-stage-otp-tls-crt__*:

Create the TLS certificates for OTP distribution using the [Following script][tls], changing the appropriate names and regions inside it.

```bash
make tls-distribution-certs
```

The command will generate three files: `ca.crt`, `deployex.key` and `deployex.crt`. Create a new version for each secret and upload each file to its respective secret using the browser's file upload button.

> [!WARNING]
> __DEPLOYEX_ERLANG_COOKIE__ and __MYAPPNAME_ERLANG_COOKIE__ __MUST__ match, as they will be used by the OTP distribution.

## 6. GCI Provisioning (Manual Steps)

For initial installations or updates to deployex, access the Google Compute Instance via SSH using the dashboard. After gaining access to the GCI, you need to grant root permissions:

```bash
my-user@myfirstapp-prod-instance:~$ sudo su
root@myfirstapp-prod-instance:/home/my-user# cd ../ubuntu/
root@myfirstapp-prod-instance:/home/ubuntu# ls
```

Check the configuration for DeployEx and your target app by editing the `deployex-config.json` file:
```bash
vi deployex-config.json
```

Authenticate using the Google Cloud CLI:
```bash
gcloud auth login
```

Follow the instructions: Copy the link provided, open it in your browser, authenticate, and then paste the verification code back into the terminal. You should see a confirmation message similar to:

```bash
You are now logged in as [my-user@gmail.com].
Your current project is [xxxxx].  You can change this setting by running:
...
```

Since the secrets are already updated, we are going to install them in the appropriate addresses
```bash
./install-otp-certificates.sh 

# Installing Certificates env: stage at /usr/local/share/ca-certificates #
Retrieving and saving ......
[OK]
```

Check that the certificates are correctly installed:
```bash
ls /usr/local/share/ca-certificates
ca.crt  myappname.crt myappname.key deployex.crt  deployex.key
```

Edit the `gcp-config.json` file to add your credentials:
```bash
vi gcp-config.json
{
  "type": "service_account" # Populate it after installation
  ...
}
```

If you are updating DeployEx, you may need to update the `deployex.sh` script. This step is not necessary during the initial installation, as the script is already installed by default. To update the script, use the following commands:

```bash
version=0.3.0
rm deployex.sh
wget https://github.com/thiagoesteves/deployex/releases/download/${version}/deployex.sh -P /home/ubuntu
chmod a+x deployex.sh
```

Run the script to install (or update) deployex:

```bash
root@ip-10-0-1-116:/home/ubuntu# ./deployex.sh --install deployex.yaml
#           Removing Deployex              #
...
# Clean and create a new directory         #
# Start systemd                            #
# Start new service                        #
Created symlink /etc/systemd/system/multi-user.target.wants/deployex.service → /etc/systemd/system/deployex.service.
```

If you need to update Deployex, follow these steps to ensure that the configuration file reflects the new version:

```bash
vi deployex.yaml
...
version: "0.7.1"
otp_version: 28
otp_tls_certificates: "/usr/local/share/ca-certificates"
os_target: "ubuntu-24.04"
...
```

Once the file is updated, run the update command:
```bash
root@ip-10-0-1-116:/home/ubuntu# ./deployex.sh --update deployex.yaml
```

> [!IMPORTANT]
> Depending on the new version of DeployEx, you may need to update both the `deployex.yaml` file and the `deployex.sh` script

At this point, DeployEx should be running. You can view the logs using the following commands:
```bash
tail -f /var/log/deployex/deployex-stdout.log
tail -f /var/log/deployex/deployex-stderr.log
```

## 7. Monitored App deployment

Once DeployEx is running, you __MUST__ deploy the monitored app. This deployment involves creating the release package and the current version JSON file in the designated storage path.

### Release Version

The release version file __MUST__ be formatted in JSON and include the following information:

```bash
{
  "version": "0.1.0-9cad9cd",
  "hash": "9cad9cd3581c69fdd02ff60765e1c7dd4599d84a",
  "pre_commands": []
}
```

The JSON file __MUST__ be stored at the following path: `/versions/{monitored_app}/{env}/current.json`

### Release package

After DeployEx fetches the release file, it will download the release package for installation. The package should be located at: `/dist/{monitored_app}/{monitored_app}-{version}.tar.gz`


### [CI/CD] Upload files to GCP from Github

Here are some useful resources with suggestions on how to automate the upload of version and release files to your environment using GitHub Actions:

 * [Gcp Workload Identity](https://mahendranp.medium.com/gcp-workload-identity-federation-with-github-actions-1d320f62417c)
 * [Guthub Actions - Cloud Storage Uploader](https://github.com/marketplace/actions/cloud-storage-uploader)
 * [Configuring OpenID Connect in Google Cloud Platform](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-google-cloud-platform)
 * [Calori Webserver Example with GCP](https://github.com/thiagoesteves/calori/tree/main/devops/gcp/terraform)

 ## 8. Setting Up HTTPS Certificates with Let's Encrypt

> [!IMPORTANT]
> Before proceeding, make sure that the DNS is correctly configured to point to the GCP instance.


 For HTTPS, you can use free certificates from [Let's encrypt](https://letsencrypt.org/getting-started/). In this example, we'll use [cert bot for ubuntu](https://certbot.eff.org/instructions?ws=nginx&os=ubuntufocal) to obtain and configure the certificates:

```bash
sudo su
apt update
apt install snapd
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
```

Before installing the certificate, make a backup of the current Nginx configuration file located at `/etc/nginx/sites-available/default`. Certbot may modify this file, so keeping a local copy ensures you can restore it if needed. Once the backup is created, run the following command:
```bash
certbot --nginx
```

This command will install Certbot and automatically configure Nginx to use the obtained certificates. After Nginx is configured, the certificate paths will be set up and will look something like this:

```bash
vi /etc/nginx/sites-available/default
 ...
           ssl_certificate /etc/letsencrypt/live/myappname.com/fullchain.pem; # managed by Certbot
           ssl_certificate_key /etc/letsencrypt/live/myappname.com/privkey.pem; # managed by Certbot
           include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
           ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
```

Update your configuration file to include the Let's Encrypt certificate paths. Find the section where it mentions:

```bash
           # Add here the letsencrypt paths
```
replace this comment with the actual certificate paths:
```bash
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "upgrade";

               proxy_pass http://deployex;
           }
           ssl_certificate /etc/letsencrypt/live/myappname.com/fullchain.pem; # managed by Certbot
           ssl_certificate_key /etc/letsencrypt/live/myappname.com/privkey.pem; # managed by Certbot
           include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
           ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
       }
```

Also, ensure that port 443 is enabled for both servers. For example:

```bash
      server {
          listen 443 ssl; # managed by Certbot
```

After modifying the configuration file, save the changes and restart Nginx:

```bash
sudo su
vi /etc/nginx/sites-available/default
# modify and save file
systemctl reload nginx
```

> [!NOTE]
> After the changes, It may require a reboot.

[tls]: https://github.com/thiagoesteves/deployex/blob/main/devops/scripts/tls-distribution-certs
[main]: https://github.com/thiagoesteves/deployex/blob/main/guides/examples/aws-elixir/terraform/environments/prod/main_example.tf_
[var]: https://github.com/thiagoesteves/deployex/blob/main/guides/examples/aws-elixir/terraform/modules/standard-account/variables.tf
