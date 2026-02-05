# Monad Validator Manager

Ansible automation for deploying and managing Monad validators on testnet and mainnet.

## Requirements

| Component | Specification |
|-----------|---------------|
| OS | Ubuntu 22.04 / 24.04 |
| CPU | 16+ cores |
| RAM | 32GB minimum |
| Storage | 2TB NVMe (TrieDB) + 500GB (OS/consensus) |
| Network | 1Gbps, static IP |

## Quick Start

```bash
# 1. Configure secrets
cp group_vars/vault.yml.example group_vars/vault.yml
vim group_vars/vault.yml

# 2. Configure inventory
cp inventory/testnet.yml inventory/local.yml
vim inventory/local.yml

# 3. Deploy
make deploy

# 4. Apply snapshot (fast sync)
make snapshot

# 5. Monitor sync
make sync
```

## Configuration

### Vault Secrets (`group_vars/vault.yml`)

```yaml
vault_validator_01_ip: "1.2.3.4"

# IKM (Initial Key Material) - generates your keys
vault_secp_ikm: "64_hex_chars"
vault_bls_ikm: "64_hex_chars"

# Keystore password
vault_keystore_password: "your_password"

# Staking (for validator registration)
vault_funded_wallet_private_key: "wallet_with_100k_MON"
vault_beneficiary_address: "0x..."
vault_auth_address: "0x..."
```

### Inventory (`inventory/local.yml`)

Copy from template and customize:

```bash
cp inventory/testnet.yml inventory/local.yml
```

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

## Commands

All commands support `NODE=<name>` to target a specific host.

```bash
# Deployment
make deploy              # Deploy validator
make snapshot            # Apply snapshot for fast sync
make execution           # Setup execution layer
make register            # Register validator (requires synced node + 100k MON)
make upgrade             # Upgrade monad packages

# Monitoring
make health              # Run health checks
make status              # Show validator status
make sync                # Show current block number
make logs                # Tail consensus logs (LINES=100)
make watch               # Stream logs in real-time

# Operations
make restart             # Restart services
make stop                # Stop services
make start               # Start services
make backup              # Backup keys and config

# Recovery
make recovery            # Run recovery playbook
make diagnose            # Show diagnostic info

# Utilities
make ping                # Test connectivity
make ssh                 # SSH to first validator
make check               # Syntax check playbooks

# Vault
make vault-edit          # Edit vault secrets
make vault-encrypt       # Encrypt vault
make vault-decrypt       # Decrypt vault
```

## Project Structure

```
├── inventory/
│   ├── local.yml            # Your inventory (gitignored)
│   ├── testnet.yml          # Testnet template
│   └── mainnet.yml          # Mainnet template
├── group_vars/
│   ├── all.yml              # Common configuration
│   ├── validators.yml       # Validator defaults
│   ├── testnet.yml          # Testnet-specific
│   ├── mainnet.yml          # Mainnet-specific
│   └── vault.yml            # Secrets (gitignored)
├── playbooks/
│   ├── deploy-validator.yml # Full deployment
│   ├── snapshot.yml         # Fast sync
│   ├── setup-execution.yml  # Execution layer
│   ├── setup-otel.yml       # OpenTelemetry
│   ├── register-validator.yml
│   ├── upgrade-node.yml
│   ├── maintenance.yml
│   └── recovery.yml
└── roles/
    ├── common/              # Firewall, fail2ban
    ├── prepare_server/      # Packages, hugepages, triedb
    ├── monad-node/          # Consensus node
    ├── validator/           # Staking CLI
    ├── execution/           # Execution layer
    ├── otel/                # OpenTelemetry collector
    ├── monitoring/          # Health checks
    └── backup/              # Backup scripts
```

## Snapshot Sync

Fast sync using official snapshots:

```bash
make snapshot
make sync      # Monitor progress
```

## Validator Registration

After node is fully synced:

```bash
make register
```

Requirements:
- Node synced (`eth_syncing` returns `false`)
- Wallet funded with 100,000+ MON

## Network Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8000 | TCP/UDP | P2P |
| 8001 | UDP | Auth |
| 8002 | TCP | RPC (localhost) |
| 4317 | TCP | OTEL GRPC |
| 8889 | TCP | Prometheus metrics |

## License

MIT
