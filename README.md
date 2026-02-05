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
vim inventory/testnet.yml   # or mainnet.yml

# 3. Encrypt secrets (optional but recommended)
ansible-vault encrypt group_vars/vault.yml

# 4. Deploy
make deploy                  # testnet (default)
make deploy ENV=mainnet      # mainnet
```

## Configuration

### Vault Secrets (`group_vars/vault.yml`)

```yaml
vault_validator_01_ip: "1.2.3.4"

# IKM (Initial Key Material) - generates your keys
# Get from: monad-keystore create --output-dir ./keys
vault_secp_ikm: "64_hex_chars"
vault_bls_ikm: "64_hex_chars"

# Keystore password (generate: openssl rand -base64 32)
vault_keystore_password: "your_password"

# Staking (for validator registration)
vault_funded_wallet_private_key: "wallet_with_100k_MON"
vault_beneficiary_address: "0x..."
vault_auth_address: "0x..."
```

### Inventory (`inventory/testnet.yml`)

```yaml
all:
  vars:
    env: testnet
  children:
    monad:
      children:
        validators:
          hosts:
            validator-01:
              ansible_host: "{{ vault_validator_01_ip }}"
              ansible_user: root
              type: validator
              setup_triedb: false  # true if fresh NVMe needs partitioning
              triedb_config:
                path: "/dev/triedb"
```

## Commands

```bash
# Deployment
make deploy              # Full deployment (ENV=testnet default)
make deploy ENV=mainnet  # Deploy to mainnet
make register            # Register validator (requires synced node + 100k MON)
make upgrade             # Upgrade monad packages

# Sync
make snapshot            # Download and apply latest snapshot (fastest sync)
make sync                # Check sync progress
make monitor             # Watch sync in real-time (Ctrl+C to exit)

# Monitoring
make health              # Run health checks
make status              # Show service status and disk usage
make logs                # View recent logs

# Operations
make restart             # Restart monad service
make backup              # Backup config and keys
make cleanup             # Cleanup old backups

# Recovery
make recovery            # Full recovery procedure
make diagnose            # Show diagnostic info

# Utilities
make ping                # Test connectivity to all hosts
make ssh                 # SSH to first validator
make check               # Syntax check playbooks

# Vault
make vault-edit          # Edit encrypted vault
make vault-encrypt       # Encrypt vault file
make vault-decrypt       # Decrypt vault file
```

## Project Structure

```
├── inventory/
│   ├── testnet.yml          # Testnet servers
│   └── mainnet.yml          # Mainnet servers
├── group_vars/
│   ├── all.yml              # Common configuration
│   ├── testnet.yml          # Testnet-specific (chain ID, URLs)
│   ├── mainnet.yml          # Mainnet-specific
│   ├── vault.yml            # Secrets (gitignored)
│   └── vault.yml.example    # Secrets template
├── playbooks/
│   ├── deploy-validator.yml
│   ├── snapshot.yml         # Fast sync via snapshot
│   ├── register-validator.yml
│   ├── upgrade-node.yml
│   ├── maintenance.yml
│   └── recovery.yml
└── roles/
    ├── common/              # Preflight checks, firewall
    ├── prepare_server/      # Packages, sysctl, hugepages, triedb
    ├── monad-node/          # Monad binary, config, systemd
    ├── validator/           # Staking CLI, registration
    ├── monitoring/          # Health checks, alerts
    └── backup/              # Backup scripts
```

## Snapshot Sync (Recommended)

Instead of syncing from genesis, use a snapshot:

```bash
make snapshot            # Downloads ~700MB, applies in minutes
make monitor             # Watch sync progress
```

## Validator Registration

After node is fully synced:

```bash
make register
```

Requirements:
- Node synced (`eth_syncing` returns `false`)
- `vault_funded_wallet_private_key` set in vault.yml
- Wallet funded with 100,000+ MON

## Network Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8000 | TCP/UDP | P2P |
| 8001 | UDP | Auth |
| 8002 | TCP | RPC (localhost only) |

## Useful Commands

```bash
# Check sync status
curl -s localhost:8002 -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","id":1}' | jq

# View logs
journalctl -u monad-consensus -f

# Service status
systemctl status monad-consensus

# Check block number
curl -s localhost:8002 -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}' | jq -r '.result' | xargs printf '%d\n'
```

## License

MIT
