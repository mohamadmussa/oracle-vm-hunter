# Oracle VM Hunter

Automated Oracle Cloud ARM VM resource hunting via GitHub Actions.

Continuously attempts to provision a free-tier **VM.Standard.A1.Flex** (ARM) instance on Oracle Cloud Infrastructure. Runs every 45 minutes via GitHub Actions cron, sweeping through CPU/memory combinations and availability domains until capacity is found.

## How It Works

1. **Cron trigger** — GitHub Actions runs every 10 minutes (or manual dispatch)
2. **Pre-flight check** — skips if a VM with the same name already exists
3. **Image resolution** — finds the latest Ubuntu 22.04 ARM image
4. **AD auto-discovery** — queries all availability domains in the region
5. **Shape sweep** — tries CPU/memory combinations in this order:
   - 2 OCPU (19 GB -> 8 GB in 1 GB steps)
   - 3 OCPU (19 GB -> 8 GB)
   - 4 OCPU (19 GB -> 8 GB)
   - Each combination is tried across all 3 availability domains
6. **First success wins** — stops immediately when a VM is created

This produces up to **108 attempts per run**, maximizing the chance of finding capacity.

## Project Structure

```
oracle-vm-hunter/
├── .github/workflows/
│   └── create-vm.yml           # GitHub Actions cron workflow
├── config/
│   └── regions.json            # Region + subnet configuration
├── scripts/
│   ├── create_vm.sh            # VM creation with shape sweep
│   └── bootstrap.sh            # Post-VM provisioning (Docker + modules)
├── modules/
│   └── kavita/
│       └── docker-compose.yml  # Kavita manga server
├── docs/
│   └── Anleitung.md            # Step-by-step setup guide
├── .env.example                # Template for local testing
└── LICENSE                     # MIT
```

## Quick Start

### Prerequisites

- Oracle Cloud account with Always Free tier
- OCI API key pair ([guide](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm))
- A VCN with a public subnet in your target region

### GitHub Actions (Production)

1. Fork this repository
2. Add these **GitHub Secrets** (Settings > Secrets > Actions):

   | Secret           | Description                         |
   |------------------|-------------------------------------|
   | `OCI_CONFIG`     | Contents of `~/.oci/config`         |
   | `OCI_KEY`        | OCI API private key (`.pem` content)|
   | `COMPARTMENT_ID` | Compartment or tenancy OCID         |

3. Edit `config/regions.json` with your region and subnet OCID:

   ```json
   [
     {
       "region": "eu-frankfurt-1",
       "subnet_id": "ocid1.subnet.oc1.eu-frankfurt-1.xxxxxxxxxxxx"
     }
   ]
   ```

4. The workflow runs automatically every 10 minutes. You can also trigger it manually via **Actions > Oracle VM Hunter > Run workflow**.

### Local Testing with `act`

```bash
# Copy and fill in your credentials
cp .env.example .env

# Run the workflow locally
act -j hunt-vm --secret-file .env
```

## Configuration

### Workflow Inputs (manual dispatch)

| Input        | Default | Description                   |
|--------------|---------|-------------------------------|
| `min_ocpus`  | 2       | Start with this many OCPUs    |
| `max_ocpus`  | 4       | Maximum OCPUs to try          |
| `max_memory` | 19      | Start memory in GB            |
| `min_memory` | 8       | Minimum acceptable memory (GB)|

### Multi-Region

Add entries to `config/regions.json` to hunt across multiple regions in parallel. Each region needs its own VCN subnet.

## Post-Provisioning

Once a VM is created, use `scripts/bootstrap.sh` to set up Docker and deploy services:

```bash
# On the new VM
curl -sL https://raw.githubusercontent.com/<user>/oracle-vm-hunter/main/scripts/bootstrap.sh | bash
```

### Available Modules

| Module   | Port | Description          |
|----------|------|----------------------|
| Kavita   | 5000 | Manga/comic server   |

## Oracle Free Tier Limits

- **Shape:** VM.Standard.A1.Flex (ARM/Ampere)
- **Max resources:** 4 OCPU / 24 GB RAM (total across all instances)
- **Always Free** — no expiration

## License

[MIT](LICENSE)
