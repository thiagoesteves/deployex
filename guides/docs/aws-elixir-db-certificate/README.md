# AWS Deployment for Elixir+Database+Certificate manager using Terraform

This guide demonstrates how to deploy DeployEx (when the application requires a DB and certificate manager) in Amazon Web Services (AWS) using Terraform to programmatically set up the environment.

## 1. Requirements

To begin, ensure the following applications are installed:

 * Terraform
 * [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

## 2. SSH Key Pair

Create an SSH key pair named, e. g. `myappname-key` by visiting the [AWS Key Pair page](https://sa-east-1.console.aws.amazon.com/ec2/home?region=sa-east-1#KeyPairs:). Save the private key in your local SSH folder (`~/.ssh`). The name `myappname-key` will be used by this file [variables.tf][var] for `bastion_key_name` variable.

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

Check the file [main.tf][main] and configure the [variables][var] according to your specific environment. These variables will be utilized across all Terraform templates to ensure correct setup.

## 5. Provisioning the Environment

Create manually the S3 bucket that will contain the terraform state, the name must follow the name defined in [main.tf][main]:

```bash
  backend "s3" {
    bucket = "myproject-myapp-terraform-state" <<<<<------ Create a S3 with this name
    key    = "terraform.tfstate"
    region = "us-east-2"
  }
```

Check you have the correct credentials to create/update resources in aws:
```bash
cat ~/.aws/credentials 
[default]
aws_access_key_id=access_key_id
aws_secret_access_key=secret_access_key
```

Once the key is configured, proceed with provisioning the environment. Navigate to the `./environments/prod` folder and execute the following commands:

```bash
terraform init # ONLY at first time
terraform plan # Check if the templates are configured correctly
terraform apply # Apply the configurations to create the environment
```

Wait for the environment to be created. Once the provisioning is complete, you can check the instance at this [address](https://console.aws.amazon.com/ec2/home).

### Updating Secret Manager

Navigate to [AWS Secrets Manager](https://console.aws.amazon.com/secretsmanager/listsecrets), locate and update the following secrets:

 *  *__prod/myappname/secret-key-base__*:

Click on the secret, then select "Retrieve Secret Value" and edit the secret by adding the new key/value pairs:

```bash
MYAPPNAME_SECRET_KEY_BASE=xxxxxxxxxx
```

 *  *__prod/myappname/erlang-cookie__*:

Click on the secret, then select "Retrieve Secret Value" and edit the secret by adding the new key/value pairs: 

```bash
MYAPPNAME_ERLANG_COOKIE=xxxxxxxxxx
```

> [!ATTENTION]
> You may need to configure additional secrets if your application requires them.

 *  *__prod/myappname/deployex/secrets__*

Click on the secret, then select "Retrieve Secret Value" and edit the secret by adding the new key/value pairs:

```bash
DEPLOYEX_SECRET_KEY_BASE=xxxxxxxxxx
DEPLOYEX_ERLANG_COOKIE=xxxxxxxxxx
DEPLOYEX_ADMIN_HASHED_PASSWORD=xxxxxxxxxx
```

 *  *__prod/myappname/deployex/otp-tls-ca__*, *__prod/myappname/deployex/otp-tls-key__*, *__prod/myappname/deployex/otp-tls-crt__*:

Create the TLS certificates for OTP distribution using the [Following script][tls], changing the appropriate names and regions inside it.

```bash
cd deployex/devops/scripts/certificates/otp-28/
./tls-distribution-certs
```

The command will generate three files: `ca.crt`, `deployex.key` and `deployex.crt`. Click in each secret in AWS, then select "Retrieve Secret Value" and edit the secret by adding them as plain text, For guidance, you can refer to this [eaxample](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-ranger-tls-certificates.html).

> [!WARNING]
> __DEPLOYEX_ERLANG_COOKIE__ and __MYAPPNAME_ERLANG_COOKIE__ __MUST__ match, as they will be used by the OTP distribution.

## 6. EC2 Provisioning (Manual Steps)

When running Terraform for the first time, AWS secrets are not yet created. Consequently, attempts to execute deployex or certificates installation will fail. Once these AWS secrets are configured, including certificates and other sensitive information, subsequent iterations of Terraform's EC2 destroy/create process will no longer require manual intervention and you can skip the next steps.

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
version: "0.9.1"
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
  "pre_commands": [\"eval Ectoapp.Migrator.create\", \"eval Ectoapp.Migrator.migrate\"] # once the DB is created for the first time, you can remove the create command
}
```

The JSON file __MUST__ be stored at the following path: `/versions/{monitored_app}/{env}/current.json`

### Release package

After DeployEx fetches the release file, it will download the release package for installation. The package should be located at: `/dist/{monitored_app}/{monitored_app}-{version}.tar.gz`


### [CI/CD] Upload files to AWS from Github

Here are some useful resources with suggestions on how to automate the upload of version and release files to your environment using GitHub Actions:

 * [Guthub Actions - S3 Downloader/Uploader](https://github.com/marketplace/actions/s3-cp)
 * [Calori Webserver Example with AWS](https://github.com/thiagoesteves/calori/tree/main/devops/aws/terraform)

[tls]: https://github.com/thiagoesteves/deployex/blob/main/devops/scripts/certificates/otp-28/tls-distribution-certs
[main]: https://github.com/thiagoesteves/deployex/blob/main/guides/docs/aws-elixir-db-certificate/terraform/environments/prod/main.tf
[var]: https://github.com/thiagoesteves/deployex/blob/main/guides/docs/aws-elixir-db-certificate/terraform/environments/prod/variables.tf