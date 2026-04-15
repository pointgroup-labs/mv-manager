# Monad Validator Manager

[![Monad](https://img.shields.io/badge/Monad-6e54ff?logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHZpZXdCb3g9IjAgMCAxNiAxNiIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48Y2lyY2xlIGN4PSI4IiBjeT0iOCIgcj0iNyIgZmlsbD0id2hpdGUiLz48L3N2Zz4=&style=for-the-badge)](https://monad.xyz)
[![Ansible](https://img.shields.io/badge/Ansible-2.15%2B-grey?logo=ansible&logoColor=white&style=for-the-badge)](https://docs.ansible.com/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)

Deploy Monad validators in minutes, not hours. Ansible automation for the entire lifecycle — setup, monitoring, upgrades, and recovery — on testnet and mainnet.

## Prerequisites

**Target server:**

| Component | Specification |
|-----------|---------------|
| OS | Ubuntu 22.04 / 24.04 |
| CPU | 16+ cores |
| RAM | 32GB minimum |
| Storage | 2TB NVMe (TrieDB) + 500GB (OS/consensus) |
| Network | 1Gbps, static IP |

**Your local machine:**

- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) 2.15+
- Python 3.10+
- `jq` (for Makefile helper scripts)
- SSH key access to target server (root or sudo user)

## Quick Start

```bash
# Clone the repo
git clone https://github.com/pointgroup-labs/mv-manager.git
cd mv-manager

# Install Ansible collections
ansible-galaxy install -r requirements.yml

# Configure secrets
cp group_vars/vault.yml.example group_vars/vault-testnet.yml
vim group_vars/vault-testnet.yml
ansible-vault encrypt group_vars/vault-testnet.yml

# Configure inventory
cp inventory/example.yml inventory/testnet.yml
vim inventory/testnet.yml     # set your server IP

# Test connectivity
make ping

# Deploy
make deploy

# Apply snapshot for fast sync
make snapshot

# Monitor sync progress
make status
```

## Configuration

### Secrets (`group_vars/vault-<env>.yml`)

Copy from the example for each network:

```yaml
# IKM (Initial Key Material) - generates your SECP and BLS keys
vault_secp_ikm: "64_hex_chars"
vault_bls_ikm: "64_hex_chars"

# Keystore password (generate with: openssl rand -base64 32)
vault_keystore_password: "your_password"

# Staking (needed for validator registration)
vault_funded_wallet_private_key: "wallet_with_100k_MON"
vault_beneficiary_address: "0x..."
vault_auth_address: "0x..."

# Telegram alerts (optional — for observability stack)
vault_telegram_bot_token: ""
vault_telegram_chat_id: ""
```

Always encrypt after editing:

```bash
make vault-encrypt          # ENV=testnet by default
make vault-encrypt ENV=mainnet
```

### Inventory (`inventory/<env>.yml`)

Create one per network (gitignored — contains server IPs):

```yaml
all:
  vars:
    env: testnet  # or mainnet

  children:
    monad:
      children:
        validators:
          hosts:
            my-validator:
              ansible_host: "1.2.3.4"
              type: validator
              validator_id: 123
              setup_triedb: true
              register_validator: false

        fullnodes:
          hosts: {}
```

**Multiple validators** — add more hosts under `validators`:

```yaml
        validators:
          hosts:
            validator-01:
              ansible_host: "1.2.3.4"
              type: validator
              validator_id: 123
              setup_triedb: true
            validator-02:
              ansible_host: "5.6.7.8"
              type: validator
              validator_id: 456
              setup_triedb: true
```

Target a specific node with `NODE=`:

```bash
make status NODE=validator-01
make restart NODE=validator-02
```

## How It Works

`make deploy` runs the full deployment pipeline through these Ansible roles:

```
common          → Preflight checks, firewall (UFW), fail2ban, sudoers
prepare_server  → System packages, kernel tuning, hugepages, TrieDB disk
monad-node      → Install monad package (apt), node.toml config, systemd service
validator       → Staking CLI, key generation, registration scripts
monitoring      → Health check scripts, alert thresholds
backup          → Automated backup scripts (daily, 7-day retention)
observability   → Prometheus, Grafana, OTEL collector, custom exporter (opt-in)
```

Each role can run independently using tags:

```bash
ansible-playbook -i inventory/testnet.yml playbooks/deploy-validator.yml --tags monad
```

## Commands

Run `make help` to see all available commands. All commands support `ENV=testnet|mainnet` and `NODE=<name>` to target a specific network or host.

### Deployment

```bash
make deploy              # Full deployment pipeline
make snapshot            # Download and apply snapshot for fast sync
make execution           # Setup execution layer (statesync socket)
make register            # Register as validator (requires synced node + 100k MON)
make rpc                 # Setup JSON-RPC server
make upgrade             # Upgrade monad packages to latest version
make observability       # Deploy observability stack (Prometheus + Grafana)
```

### Monitoring

```bash
make health              # Run health checks
make status              # Validator dashboard (sync, voting, stake, resources)
make logs                # Tail logs (SVC=consensus|execution|rpc LINES=50)
make watch               # Stream logs with color (SVC=consensus|execution|rpc)
make grafana             # Open Grafana via SSH tunnel
```

### Operations

```bash
make restart             # Restart execution → consensus → rpc
make stop                # Stop all monad services
make start               # Start execution → consensus → rpc
make backup              # Backup keys and config
make commission          # Set commission rate (RATE=20 NODE=name)
```

### Recovery

```bash
make recovery            # Run full recovery playbook
make diagnose            # Show diagnostic info (disk, memory, services)
```

### Utilities

```bash
make ping                # Test SSH connectivity
make hardware            # Show server hardware specs (CPU, RAM, storage)
make speedtest           # Run bandwidth speedtest
make ssh                 # SSH into first validator
make check               # Syntax check all playbooks
```

### Vault

```bash
make vault-edit          # Edit vault secrets (decrypt → edit → re-encrypt)
make vault-encrypt       # Encrypt vault file
make vault-decrypt       # Decrypt vault file
```

## Snapshot Sync

New nodes should sync from a snapshot rather than from genesis:

```bash
make deploy              # Deploy node first
make snapshot            # Download and apply latest snapshot
make status              # Monitor block height
```

The snapshot is downloaded from Monad's official CDN. Depending on your bandwidth, this can take 30–60 minutes. After applying, the node will catch up the remaining blocks automatically.

## Validator Registration

After your node is fully synced:

```bash
make register
```

**Requirements:**
- Node must be synced (`eth_syncing` returns `false`)
- Wallet funded with **100,000+ MON** for self-stake
- `register_validator: true` set in inventory
- Vault configured with `vault_funded_wallet_private_key` and addresses

The registration script stakes MON, submits your validator keys on-chain, and begins participating in consensus once the stake activates.

## Network Ports

**Validator:**

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 8000 | TCP/UDP | Public | P2P consensus |
| 8001 | UDP | Public | Auth |
| 8002 | TCP | Localhost only | JSON-RPC |

**Fullnode:**

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 8010 | TCP/UDP | Public | P2P consensus |
| 8011 | UDP | Public | Auth |
| 8090 | TCP | Localhost only | JSON-RPC |

**Observability (opt-in):**

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 3000 | TCP | Public | Grafana dashboard |
| 9090 | TCP | Localhost only | Prometheus (Docker internal) |
| 4317 | TCP | Localhost only | OTEL gRPC (Docker internal) |

Only P2P and auth ports are exposed publicly. RPC and internal services are bound to localhost. Grafana (3000) is exposed through the firewall when the observability stack is deployed.

## Observability

An optional monitoring stack that runs alongside the validator node:

```bash
make observability       # Deploy the stack
make grafana             # Open Grafana via SSH tunnel
```

**What's included:**
- **Grafana** dashboard with validator health, staking metrics, consensus stats, and system resources
- **Prometheus** scraping node_exporter and custom monad metrics
- **OTEL Collector** forwarding telemetry to Monad infra
- **Custom monad exporter** that queries the RPC and staking contract every 30s, producing Prometheus metrics via textfile collector

**Metrics exported** by the monad exporter:
- Block height, sync status, epoch
- Validator stake, pending stake, unclaimed rewards, commission
- Wallet balance
- Consensus round, voting rate, skipped rounds, network participation, proposals

**Alerting** (optional): Configure `vault_telegram_bot_token` and `vault_telegram_chat_id` in vault for Telegram alerts on sync loss, high disk, and service failures.

The stack is opt-in: set `observability_enabled: true` in your inventory or run `make observability` as a standalone playbook.

## Troubleshooting

**Node won't start**
```bash
make diagnose                # Check disk, memory, service status
make logs LINES=200          # View recent consensus logs on the server
```

**Sync is stuck or slow**
```bash
make status                  # Check current block height
make logs SVC=consensus LINES=200  # Look for errors in recent logs
make snapshot                # Re-apply snapshot if needed
```

**Connection refused / can't reach node**
```bash
make ping                    # Test SSH connectivity
make hardware                # Verify server specs
# Check firewall: ports 8000 (TCP/UDP) and 8001 (UDP) must be open
```

**TrieDB mount issues**
```bash
make diagnose                # Check disk partitions
# Verify NVMe device path matches triedb_config.drive in all.yml
# Default: /dev/nvme0n1
```

**Recovery from crash**
```bash
make recovery                # Full recovery: check services, repair data, restart
```

## Contributing

Contributions are welcome. Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-change`)
3. Follow [Conventional Commits](https://www.conventionalcommits.org/) for commit messages
4. Submit a pull request

## License

[MIT](LICENSE)
