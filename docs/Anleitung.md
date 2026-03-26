# Guide: Project Setup

Step-by-step documentation of all CLI commands and decisions made during this project.

---

## 1. Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- Required scopes: `repo`, `workflow`, `delete_repo`

```bash
# Check authentication status
gh auth status

# If delete_repo scope is needed
gh auth refresh -h github.com -s delete_repo
```

---

## 2. Repository Creation

We chose a **public** repository with the **MIT license** to protect ourselves legally (AS IS disclaimer, no liability).

```bash
# Create public repo with MIT license
gh repo create oracle-vm-hunter \
  --public \
  --license mit \
  --description "Automated Oracle Cloud ARM VM resource hunting via GitHub Actions" \
  --clone

# This clones the repo into ./oracle-vm-hunter
cd oracle-vm-hunter
```

> **Note:** If the repo already exists and you need a clean start:
> ```bash
> gh repo delete mohamadmussa/oracle-vm-hunter --yes
> ```
> Then re-run the create command above.

---

## 3. Branch Strategy

We work on feature branches and merge into `main` via pull requests.

```bash
# Create and switch to the initial setup branch
git checkout -b feature/initial-setup
```

---

## 4. Project Structure

```text
oracle-vm-hunter/
├── .github/workflows/
│   └── create-vm.yml          # GitHub Actions cron workflow (multi-region matrix)
├── config/
│   └── regions.json           # Region config (region + subnet per entry)
├── scripts/
│   ├── create_vm.sh           # VM creation + smart scaling + auto-AD discovery
│   └── bootstrap.sh           # Post-VM provisioning (Docker + modules)
├── modules/
│   └── kavita/
│       └── docker-compose.yml # Kavita manga server
├── docs/
│   └── Anleitung.md           # This file
└── .env.example               # Template for local testing with act
```

---

## 5. VM Hunter Script (`scripts/create_vm.sh`)

The script implements a **CPU/Memory sweep strategy**:
1. Check if VM already exists (skip if running)
2. Resolve the latest Ubuntu 22.04 ARM image
3. **Auto-discover** Availability Domains (no manual config needed)
4. Sweep through all CPU/RAM combinations:
   - CPU: 2 OCPU → 3 OCPU → 4 OCPU (smaller = more likely available)
   - Memory: MAX_MEMORY → MIN_MEMORY in 1 GB steps per CPU level
   - ADs: try all 3 Availability Domains per combination
5. Stop immediately on first successful launch (`break 3`)

This creates up to **108 attempts per run** (3 CPU levels × 12 memory steps × 3 ADs).

Key environment variables:

| Variable              | Default | Description                            |
|-----------------------|---------|----------------------------------------|
| `REGION`              | (config)| Region override (e.g. `eu-frankfurt-1`)|
| `SUBNET_ID`           | —       | Subnet OCID (region-specific)          |
| `MIN_OCPUS`           | 2       | Start with this many OCPUs             |
| `MAX_OCPUS`           | 4       | Maximum OCPUs to try                   |
| `MAX_MEMORY`          | 19      | Start memory (GB), steps down          |
| `MIN_MEMORY`          | 8       | Minimum acceptable memory (GB)         |
| `DISPLAY_NAME`        | free-arm-instance | VM display name              |

---

## 6. Multi-Region Setup

### How it works

The workflow reads `config/regions.json` and runs **all regions in parallel** using a GitHub Actions matrix strategy. Each region gets its own job.

### Adding a new region

1. Create a VCN + public subnet in the new region (Oracle Console > Networking > VCN Wizard)
2. Add the region to `config/regions.json`:

```json
{
  "region": "eu-paris-1",
  "subnet_id": "ocid1.subnet.oc1.eu-paris-1.xxxxxxxxxxxx"
}
```

### Available Oracle Free Tier regions (EU)

| Region           | Location    |
|------------------|-------------|
| `eu-frankfurt-1` | Frankfurt   |
| `eu-amsterdam-1` | Amsterdam  |
| `eu-paris-1`    | Paris       |
| `eu-madrid-1`   | Madrid      |
| `eu-marseille-1` | Marseille  |
| `eu-milan-1`    | Milan       |
| `eu-stockholm-1` | Stockholm  |
| `eu-zurich-1`   | Zurich      |

---

## 7. GitHub Actions Workflow (`.github/workflows/create-vm.yml`)

Runs every 10 minutes via cron. Hunts across **all configured regions in parallel**.

```yaml
on:
  schedule:
    - cron: "*/10 * * * *"
  workflow_dispatch:        # manual trigger with inputs
```

The workflow has two jobs:
1. **load-regions** — reads `config/regions.json` and builds the matrix
2. **hunt-vm** — runs `create_vm.sh` for each region (parallel, `fail-fast: false`)

---

## 7. Bootstrap Script (`scripts/bootstrap.sh`)

Runs on the VM after creation to install Docker and deploy services.

Module toggles via environment variables:

```bash
ENABLE_KAVITA=true      # Manga server (default: true)
ENABLE_NEXTCLOUD=false  # Cloud storage (default: false)
ENABLE_BACKUP=false     # Backup module (default: false)
```

---

## 8. Modules

Each module lives in `modules/<name>/docker-compose.yml`. Currently available:

- **kavita** — Manga/comic server on port 5000

To add a new module, create `modules/<name>/docker-compose.yml` and add the toggle to `bootstrap.sh`.

---

## 9. Local Testing with `act`

Before pushing to GitHub, test the workflow locally using [act](https://github.com/nektos/act).

### Setup

```bash
# Copy the example env file and fill in your real OCI values
cp .env.example .env

# Edit .env with your credentials
# IMPORTANT: .env is in .gitignore — it will NOT be committed
```

### Run the workflow

```bash
# Dry run (just validate the workflow)
act -n

# Run the workflow with secrets from .env
act -j hunt-vm --secret-file .env

# Run with manual trigger inputs
act workflow_dispatch -j hunt-vm --secret-file .env \
  --input ocpus=2 --input memory=12
```

### Troubleshooting

- If `act` fails with image issues, use: `act -P ubuntu-latest=catthehacker/ubuntu:act-latest`
- Ensure `.env` contains all required variables (see `.env.example`)

---

## 10. GitHub Secrets (for production)

Once local tests pass, configure secrets in GitHub:

Go to: **Settings > Secrets and variables > Actions**

| Secret                 | Description                                         |
|------------------------|-----------------------------------------------------|
| `OCI_CONFIG`           | Contents of `~/.oci/config`                         |
| `OCI_KEY`              | Contents of the OCI API private key (`.pem`)        |
| `COMPARTMENT_ID`       | OCI compartment OCID                                |
| `SUBNET_ID`            | VCN subnet OCID (only needed for single-region testing) |

---

## 11. Next Steps

- [x] Fill in `.env` with real OCI credentials
- [x] Test workflow locally with `act`
- [ ] Configure GitHub Secrets for production
- [ ] Optimize sweep speed (parallel ADs, larger memory steps)
- [ ] Add Cloudflare tunnel integration
- [ ] Add notification on success (Telegram/Discord)
- [ ] Add persistent storage (Rclone to R2/B2)
- [ ] Add backup module
