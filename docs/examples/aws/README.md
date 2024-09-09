# AWS Deployment (with terraform)

This is an example of how to install deployex in an AWS cloud using terraform to programatically setup the enviromnent.

## Setup

To begin, ensure the following applications are installed:

 * Terraform
 * [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

### 1. SSH Key Pair

Create an SSH key pair named, e. g. `myappname-web-ec2` by visiting the [AWS Key Pair page](https://sa-east-1.console.aws.amazon.com/ec2/home?region=sa-east-1#KeyPairs:). Save the private key in your local SSH folder (`~/.ssh`). The name `myappname-web-ec2` will be used by this file `devops/terraform/modules/standard-account/variables.tf` within terraform templates.

### 2. Environment Secrets

Ensure you have access to the following secrets for storage in AWS Secrets Manager:

 - DEPLOYEX_SECRET_KEY_BASE
 - DEPLOYEX_ERLANG_COOKIE
 - DEPLOYEX_ADMIN_HASHED_PASSWORD
 - MYAPPNAME_SECRET_KEY_BASE
 - MYAPPNAME_ERLANG_COOKIE

### 3. MYAPPNAME_PHX_HOST Configuration

In the file `devops/terraform/environments/prod/main.tf`, verify and set the *__server_dns__* variable according to the specific environment, such as `myappname.com.br`. This variable will be used in all terraform templates to set-up correctly the hostname.

### 4. Provisioning the Environment

Check you have the correct credentials to create/update resources in aws:
```bash
cat ~/.aws/credentials 
[default]
aws_access_key_id=access_key_id
aws_secret_access_key=secret_access_key
```

Once the key is configured, proceed with provisioning the environment. Navigate to the `devops/terraform/environments/prod` folder and execute the following commands:

```bash
terraform plan # Check if the templates are configured correctly
terraform apply # Apply the configurations to create the environment
```

Wait for the environment to be created. Afterward, update the variables in the *__myappname-prod-secrets__* secret in the [AWS Secrets Manager](https://sa-east-1.console.aws.amazon.com/secretsmanager/listsecrets?region=sa-east-1) with the corresponding values (You may need to configure more secrets if you application requires it):

```bash
# Update the secrets
MYAPPNAME_SECRET_KEY_BASE=xxxxxxxxxx
MYAPPNAME_ERLANG_COOKIE=xxxxxxxxxx
```

Additionally, create the TLS certificates for the OTP distribution using the [Following script](../../../devops/scripts/tls-distribution-certs), changing the appropriate names and regions inside it.

```bash
make tls-distribution-certs
```

*__PS__*: you will also need to add them as plain text as explained [here](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-ranger-tls-certificates.html)

Add the following certificates:
 - *__myappname-stage-otp-tls-ca__*
 - *__myappname-stage-otp-tls-key__*
 - *__myappname-stage-otp-tls-crt__*

Configure the Deployex secrets, which should be added in the *__deployex-myappname-prod-secrets__* in the [AWS Secrets Manager](https://sa-east-1.console.aws.amazon.com/secretsmanager/listsecrets?region=sa-east-1) with the corresponding values.

 ```bash
DEPLOYEX_SECRET_KEY_BASE=xxxxxxxxxx
DEPLOYEX_ERLANG_COOKIE=xxxxxxxxxx
DEPLOYEX_ADMIN_HASHED_PASSWORD=xxxxxxxxxx
```

*__PS__*: __DEPLOYEX_ERLANG_COOKIE__ and __MYAPPNAME_ERLANG_COOKIE__ __MUST__ match because they will be used by the OTP distribution.

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

Run the script to install the certificates:
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