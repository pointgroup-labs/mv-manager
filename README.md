# Monad Validator

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
vim inventory/testnet.yml

# 3. Deploy
make deploy

# 4. Apply snapshot (fast sync)
make snapshot

# 5. Monitor sync
make watch
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

### Inventory (`inventory/testnet.yml`)

```yaml
validators:
  hosts:
    validator-01:
      ansible_host: "{{ vault_validator_01_ip }}"
      ansible_user: root
      type: validator
      setup_triedb: false
      triedb_config:
        path: "/dev/triedb"
```

## Commands

```bash
# Deployment
make deploy              # Full deployment
make deploy ENV=mainnet  # Deploy to mainnet
make snapshot            # Fast sync via snapshot
make register            # Register validator (requires 100k MON)
make upgrade             # Upgrade monad packages

# Components
make execution           # Setup execution layer
make otel                # Setup OpenTelemetry metrics

# Monitoring
make health              # Run health checks
make status              # Show service status
make sync                # Check sync progress
make watch               # Watch sync in real-time
make logs                # View recent logs

# Operations
make restart             # Restart monad service
make backup              # Backup config and keys
make cleanup             # Cleanup old backups

# Recovery
make recovery            # Full recovery procedure
make diagnose            # Show diagnostic info

# Utilities
make ping                # Test connectivity
make ssh                 # SSH to validator
make check               # Syntax check playbooks

# Vault
make vault-edit          # Edit encrypted vault
make vault-encrypt       # Encrypt vault file
make vault-decrypt       # Decrypt vault file

# Help
make help                # Show all commands
```

## Project Structure

```
├── inventory/
│   ├── testnet.yml
│   └── mainnet.yml
├── group_vars/
│   ├── all.yml              # Common configuration
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
make snapshot    # Downloads and applies snapshot
make watch       # Monitor sync progress
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
