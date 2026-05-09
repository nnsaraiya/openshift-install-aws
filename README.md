# openshift-install-aws

Fully automated installation of the latest OpenShift on AWS using the
Installer-Provisioned Infrastructure (IPI) method, managed via Ansible.

## Prerequisites

| Requirement | Notes |
|---|---|
| Ansible ≥ 2.15 | `pip install --user ansible` |
| AWS CLI v2 | macOS: `brew install awscli` · Linux: see [AWS docs](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| `htpasswd` utility | macOS: `brew install httpd` · Debian/Ubuntu: `apt install apache2-utils` · RHEL/Fedora: `dnf install httpd-tools` |
| AWS account with [required IAM permissions](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-account.html) | |
| Route53 **public** hosted zone for your base domain | Must exist before install |
| Red Hat pull secret | Download from https://console.redhat.com/openshift/install/pull-secret |

> **Apple Silicon (M-series) Mac:** the `openshift-install` binary is downloaded as
> x86_64 and runs via Rosetta 2. This is required to deploy amd64 clusters, which
> is the default (`ocp_cluster_arch: amd64`). The `oc`/`kubectl` clients download
> as native arm64 for performance.

> **Linux:** Ansible is typically installed via `pip install --user ansible`; ensure
> `~/.local/bin` is on your `PATH`. The playbooks automatically download the correct
> Linux binaries (`openshift-install-linux.tar.gz`, `openshift-client-linux.tar.gz`)
> based on `ansible_system`.

## Quick Start

### 1. Install Ansible collections

```bash
make setup
```

### 2. Configure your vault password

```bash
echo "your-strong-password" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

### 3. Fill in cluster variables

Edit [`inventory/group_vars/all/main.yml`](inventory/group_vars/all/main.yml):

| Variable | Description |
|---|---|
| `ocp_cluster_name` | Unique cluster name |
| `ocp_base_domain` | Route53 public hosted zone domain |
| `ocp_aws_region` | Target AWS region |
| `ocp_aws_availability_zones` | List of 1 or 3 AZs |
| `ocp_master_instance_type` | Control plane instance type (amd64: `m6i.xlarge`) |
| `ocp_worker_instance_type` | Worker instance type (amd64: `m6i.2xlarge`) |
| `ocp_cluster_arch` | Cluster node architecture: `amd64` or `arm64` |
| `ocp_version` | OCP version — `latest` or pinned e.g. `4.17.3` |

### 4. Fill in secrets and encrypt the vault

```bash
# Edit with plain text first
$EDITOR inventory/group_vars/all/vault.yml

# Encrypt it
make encrypt-vault
```

Required vault values:

| Variable | Description |
|---|---|
| `vault_aws_access_key_id` | AWS access key |
| `vault_aws_secret_access_key` | AWS secret key |
| `vault_pull_secret` | Full JSON string from Red Hat console (paste as-is, no extra quotes) |
| `vault_ssh_public_key` | Full SSH public key as output by `cat ~/.ssh/id_rsa.pub` |
| `vault_admin_password` | Password for the `cluster-admin` htpasswd user (used in Day 2) |

> **Pull secret:** paste the raw JSON exactly as downloaded — it uses double quotes.
> Do not wrap it in extra quotes in the YAML file.
>
> **SSH key:** paste the full key including the `ssh-rsa` prefix, exactly as shown
> by `cat ~/.ssh/id_rsa.pub`. Do not add the prefix again.

### 5. Validate prerequisites (no AWS resources created)

```bash
make validate
```

This checks AWS credentials, Route53 hosted zone, downloads the installer binary,
and generates `install-config.yaml` — without creating any cluster resources.

### 6. Install the cluster

```bash
make install
```

This runs **cluster installation only**. Day 2 configuration is **not** applied
automatically. The install takes ~40–45 minutes. Progress is logged to:

```
.openshift-install/clusters/<cluster-name>/.openshift_install.log
```

### 7. Apply Day 2 configuration

Once the cluster is up, run Day 2 explicitly:

```bash
make day2
```

Day 2 configures:
- **HTPasswd identity provider** with a `cluster-admin` user
- **cluster-admin RBAC** for that user
- **kubeadmin removal** (only after verifying htpasswd login works)
- **Image registry** set to Managed state

### 8. Access the cluster

```bash
export KUBECONFIG=.openshift-install/clusters/<cluster-name>/auth/kubeconfig
.openshift-install/bin/oc get nodes
```

**Console URL:** `https://console-openshift-console.apps.<cluster-name>.<base-domain>`

> **First browser login:** The cluster uses a self-signed TLS certificate. You must
> accept the certificate warning for **both** domains before the console login will
> work:
> - `https://oauth-openshift.apps.<cluster-name>.<base-domain>`
> - `https://console-openshift-console.apps.<cluster-name>.<base-domain>`
>
> After accepting both, log in with username `cluster-admin` and your
> `vault_admin_password`. Each new cluster generates new certificates — clear
> your browser's cached exceptions when recreating a cluster.

---

## Project Layout

```
aws/
├── ansible.cfg
├── Makefile                        # Convenience targets
├── requirements.yml                # Ansible collection deps
├── inventory/
│   ├── hosts
│   └── group_vars/all/
│       ├── main.yml                # Cluster configuration
│       └── vault.yml               # Encrypted secrets (never commit unencrypted)
├── playbooks/
│   ├── validate.yml                # Pre-flight checks only
│   ├── install.yml                 # Cluster install (Day 2 excluded)
│   ├── destroy.yml                 # Tear down cluster
│   └── day2/
│       └── configure.yml           # Day 2 — run explicitly after install
└── roles/
    ├── ocp_prereqs/                # Download binaries, validate AWS, generate install-config
    ├── ocp_install/                # Run openshift-install, show access summary
    └── ocp_day2/                   # HTPasswd IDP, RBAC, kubeadmin removal, registry
```

## Common Operations

```bash
make validate          # Pre-flight checks (AWS creds, Route53, installer binary)
make install           # Install cluster only — Day 2 NOT included
make day2              # Apply Day 2 config to an existing cluster
make install-with-day2 # Install cluster AND Day 2 in one shot
make destroy           # Destroy cluster and all AWS resources (prompts for confirmation)
make edit-vault        # Edit encrypted vault secrets
make encrypt-vault     # Encrypt vault.yml
make decrypt-vault     # Decrypt vault.yml
```

## Typical Workflow

```
make validate          ← verify everything before spending time/money
make install           ← ~40-45 min
make day2              ← configure auth, remove kubeadmin
# ... use cluster ...
make destroy           ← clean up when done
```

## Pinning an OCP Version

`ocp_version: "latest"` always pulls the current stable release. To pin:

```yaml
ocp_version: "4.21.14"
```

## Security Notes

- `vault.yml` **must** be encrypted before committing — run `make encrypt-vault`.
- `.openshift-install/` is git-ignored. It contains the kubeconfig, kubeadmin
  password, and Terraform state. Back it up externally (S3, Vault, etc.).
- `install-config.yaml.bak` inside the cluster workspace contains your pull secret
  in plain text — protect the `.openshift-install/` directory.
- Each new cluster gets a new kubeadmin password stored at
  `.openshift-install/clusters/<name>/auth/kubeadmin-password`. After `make day2`
  the kubeadmin secret is removed from the cluster; only `cluster-admin`
  (htpasswd) remains.
