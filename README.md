# Monad Validator Manager

[![Monad](https://img.shields.io/badge/Monad-purple?logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHZpZXdCb3g9IjAgMCAxNiAxNiIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48Y2lyY2xlIGN4PSI4IiBjeT0iOCIgcj0iNyIgZmlsbD0id2hpdGUiLz48L3N2Zz4=&style=for-the-badge)](https://monad.xyz)
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
cp group_vars/vault.yml.example group_vars/vault.yml
vim group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml

# Configure inventory
cp inventory/testnet.yml inventory/local.yml
vim inventory/local.yml     # set your server IP

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

### Secrets (`group_vars/vault.yml`)

Copy from the example and fill in your values:

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
```

Always encrypt after editing:

```bash
make vault-encrypt
```

### Inventory (`inventory/local.yml`)

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
              setup_triedb: true
            validator-02:
              ansible_host: "5.6.7.8"
              type: validator
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
monad-node      → Download binaries, node.toml config, systemd service
validator       → Staking CLI, key generation, registration scripts
monitoring      → Health check scripts, alert thresholds
backup          → Automated backup scripts (daily, 7-day retention)
```

Each role can run independently using tags:

```bash
ansible-playbook -i inventory/local.yml playbooks/deploy-validator.yml --tags monad
```

## Commands

Run `make help` to see all available commands. All commands support `NODE=<name>` to target a specific host.

### Deployment

```bash
make deploy              # Full deployment pipeline
make snapshot            # Download and apply snapshot for fast sync
make execution           # Setup execution layer (statesync socket)
make register            # Register as validator (requires synced node + 100k MON)
make upgrade             # Upgrade monad packages to latest version
```

### Monitoring

```bash
make health              # Run health checks
make status              # Show validator status (keys, sync, peers)
make logs                # Tail consensus logs (LINES=100)
make watch               # Stream logs in real-time with color
```

### Operations

```bash
make restart             # Restart consensus + execution services
make stop                # Stop all monad services
make start               # Start execution, then consensus
make backup              # Backup keys and config
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

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 8000 | TCP/UDP | Public | P2P consensus |
| 8001 | UDP | Public | Auth |
| 8002 | TCP | Localhost only | JSON-RPC |
| 4317 | TCP | Localhost only | OTEL gRPC (if enabled) |
| 8889 | TCP | Localhost only | Prometheus metrics (if enabled) |

Only P2P ports (8000, 8001) are exposed publicly. RPC and metrics are bound to localhost by default.

## Troubleshooting

**Node won't start**
```bash
make diagnose                # Check disk, memory, service status
journalctl -u monad-consensus -n 50    # View service logs on the server
```

**Sync is stuck or slow**
```bash
make status                  # Check current block height
make logs LINES=200          # Look for errors in recent logs
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
