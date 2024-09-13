# AWS Deployment with Terraform

This guide demonstrates how to deploy DeployEx in Amazon Web Services (AWS) using Terraform to programmatically set up the environment.

## Setup

To begin, ensure the following applications are installed:

 * Terraform
 * [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

### 1. SSH Key Pair

Create an SSH key pair named, e. g. `myappname-web-ec2` by visiting the [AWS Key Pair page](https://sa-east-1.console.aws.amazon.com/ec2/home?region=sa-east-1#KeyPairs:). Save the private key in your local SSH folder (`~/.ssh`). The name `myappname-web-ec2` will be used by this file `devops/terraform/modules/standard-account/variables.tf` within terraform templates.

### 2. Environment Secrets

Ensure you have access to the following secrets for storage in Secrets Manager:

| SECRET NAME | EXAMPLE | SOURCE |
|----------|-------------|------:|
| DEPLOYEX_SECRET_KEY_BASE | 42otsNl...Fpq3dIJ02 | mix phx.gen.secret |
| DEPLOYEX_ERLANG_COOKIE| my-cookie |  |
| DEPLOYEX_ADMIN_HASHED_PASSWORD | $2b$12$...3Lu6ys538TW | Bcrypt.hash_pwd_salt("my-pass") |
| MYAPPNAME_SECRET_KEY_BASE | 42otsNl...Fpq3dIJ02 | mix phx.gen.secret |
| MYAPPNAME_ERLANG_COOKIE | my-cookie |  |

### 3. Variables Configuration

Rename the file [main_example.tf_](./environments/prod/main_example.tf_) to [main.tf](./environments/prod/main.tf) and verify and configure the variables according to your specific environment. Ensure that you also review and update the [variables file](./modules/standard-account/variables.tf). These variables will be utilized across all Terraform templates to ensure correct setup.

### 4. Provisioning the Environment

Check you have the correct credentials to create/update resources in aws:
```bash
cat ~/.aws/credentials 
[default]
aws_access_key_id=access_key_id
aws_secret_access_key=secret_access_key
```

Once the key is configured, proceed with provisioning the environment. Navigate to the `./environments/prod` folder and execute the following commands:

```bash
terraform plan # Check if the templates are configured correctly
terraform apply # Apply the configurations to create the environment
```

Wait for the environment to be created. Once the provisioning is complete, you can check the instance at this [address](https://console.aws.amazon.com/ec2/home).

#### Updating Secret Manager

Navigate to [AWS Secrets Manager](https://console.aws.amazon.com/secretsmanager/listsecrets), locate and update the following secrets:

 *  *__myappname-prod-secrets__*:

Click on the secret, then select "Retrieve Secret Value" and edit the secret by adding the new key/value pairs: (You may need to configure additional secrets if your application requires them)

```bash
# Update the secrets
MYAPPNAME_SECRET_KEY_BASE=xxxxxxxxxx
MYAPPNAME_ERLANG_COOKIE=xxxxxxxxxx
```

* *__deployex-myappname-prod-secrets__*

Click on the secret, then select "Retrieve Secret Value" and edit the secret by adding the new key/value pairs:

 ```bash
DEPLOYEX_SECRET_KEY_BASE=xxxxxxxxxx
DEPLOYEX_ERLANG_COOKIE=xxxxxxxxxx
DEPLOYEX_ADMIN_HASHED_PASSWORD=xxxxxxxxxx
```

 *  *__myappname-stage-otp-tls-ca__*, *__myappname-stage-otp-tls-key__*, *__myappname-stage-otp-tls-crt__*:

Create the TLS certificates for OTP distribution using the [Following script](../../../devops/scripts/tls-distribution-certs), changing the appropriate names and regions inside it.

```bash
make tls-distribution-certs
```

The command will generate three files: `ca.crt`, `deployex.key` and `deployex.crt`. Click in each secret in AWS, then select "Retrieve Secret Value" and edit the secret by adding them as plain text, For guidance, you can refer to this [eaxample](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-ranger-tls-certificates.html).

> [!WARNING]
> __DEPLOYEX_ERLANG_COOKIE__ and __MYAPPNAME_ERLANG_COOKIE__ __MUST__ match, as they will be used by the OTP distribution.

### 5. EC2 Provisioning (Manual Steps)

When running Terraform for the first time, AWS secrets are not yet created. Consequently, attempts to execute deployex or certificates installation will fail. Once these AWS secrets, including certificates and other sensitive information, are updated, subsequent iterations of Terraform's EC2 destroy/create process will no longer require manual intervention.

For initial installations or updates to deployex, follow these steps:

*__PS__*: make sure you have the pair myappname-web-ec2.pem saved in `~/.ssh/`

```bash
ssh -i "myappname-web-ec2.pem" ubuntu@ec2-52-67-178-12.sa-east-1.compute.amazonaws.com
ubuntu@ip-10-0-1-56:~$
```

After getting access to EC2, you need to grant root permissions:

```bash
ubuntu@ip-10-0-1-56:~$ sudo su
root@ip-10-0-1-56:/home/ubuntu$
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
If you are updating DeployEx, you may need to update the `deployex.sh` script. This step is not necessary during the initial installation, as the script is already installed by default. To update the script, use the following commands:

```bash
version=0.3.0
rm deployex.sh
wget https://github.com/thiagoesteves/deployex/releases/download/${version}/deployex.sh -P /home/ubuntu
chmod a+x deployex.sh

Run the script to install (or update) deployex:

```bash
root@ip-10-0-1-116:/home/ubuntu# ./deployex.sh --install deployex-config.json
#           Removing Deployex              #
...
# Clean and create a new directory         #
# Start systemd                            #
# Start new service                        #
Created symlink /etc/systemd/system/multi-user.target.wants/deployex.service → /etc/systemd/system/deployex.service.
```

If you need to update Deployex, follow these steps to ensure that the configuration file reflects the new version:

```bash
vi deployex-config.json
{
 ...
  "version": "0.3.0-rc15",
  "os_target": "ubuntu-20.04",
  ...
}
```

Once the file is updated, run the update command:
```bash
root@ip-10-0-1-116:/home/ubuntu# ./deployex.sh --update deployex-config.json
```

> [!IMPORTANT]
> Depending on the new version of DeployEx, you may need to update both the `deployex-config.json` file and the `deployex.sh` script

At this point, DeployEx should be running. You can view the logs using the following commands:
```bash
tail -f /var/log/deployex/deployex-stdout.log
tail -f /var/log/deployex/deployex-stderr.log
```

### 6. Monitored App deployment

Once DeployEx is running, you __MUST__ deploy the monitored app. This deployment involves creating the release package and the current version JSON file in the designated storage path.

#### Release Version

The release version file __MUST__ be formatted in JSON and include the following information:

```bash
{
  "version": "0.1.0-9cad9cd",
  "hash": "9cad9cd3581c69fdd02ff60765e1c7dd4599d84a",
  "pre_commands": []
}
```

The JSON file __MUST__ be stored at the following path: `/versions/{monitored_app}/{env}/current.json`

#### Release package

After DeployEx fetches the release file, it will download the release package for installation. The package should be located at: `/dist/{monitored_app}/{monitored_app}-{version}.tar.gz`


#### [CI/CD] Upload files to AWS from Github

Here are some useful resources with suggestions on how to automate the upload of version and release files to your environment using GitHub Actions:

 * [Guthub Actions - S3 Downloader/Uploader](https://github.com/marketplace/actions/s3-cp)
 * [Calori Webserver Example with AWS](https://github.com/thiagoesteves/calori/tree/main/devops/aws/terraform)

 ### 7. Setting Up HTTPS Certificates with Let's Encrypt

> [!IMPORTANT]
> Before proceeding, make sure that the DNS is correctly configured to point to the AWS instance.


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

The commands above will configure Nginx for the correct routing. Once this is set up, verify that the monitored app’s configuration file `/config/runtime.exs` points to the correct SCHEME/HOST/PORT, For example:

```elixir
    url: [host: "myappname.com", port: 443, scheme: "https"],
```
