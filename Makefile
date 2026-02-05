ENV ?= testnet
VAULT_ARGS ?=
INV := -i inventory/$(ENV).yml
.DEFAULT_GOAL := help
G := \033[32m
N := \033[0m

.PHONY: deploy register upgrade snapshot health status sync monitor logs restart backup cleanup recovery diagnose ping ssh check vault-edit vault-encrypt vault-decrypt help

# Deployment
deploy: ## Full validator deployment (ENV=testnet|mainnet)
	ansible-playbook $(INV) playbooks/deploy-validator.yml $(VAULT_ARGS)

register: ## Register validator (requires synced node + 100k MON)
	ansible-playbook $(INV) playbooks/register-validator.yml $(VAULT_ARGS)

upgrade: ## Upgrade monad packages
	ansible-playbook $(INV) playbooks/upgrade-node.yml $(VAULT_ARGS)

snapshot: ## Download and apply latest snapshot
	ansible-playbook $(INV) playbooks/snapshot.yml $(VAULT_ARGS)

# Monitoring
health: ## Run health checks
	ansible-playbook $(INV) playbooks/maintenance.yml --tags health $(VAULT_ARGS)

status: ## Show service status and disk usage
	ansible-playbook $(INV) playbooks/maintenance.yml --tags status $(VAULT_ARGS)

sync: ## Check node sync progress
	ansible-playbook $(INV) playbooks/maintenance.yml --tags sync $(VAULT_ARGS)

monitor: ## Watch sync progress in real-time
	@ssh root@$$(grep vault_validator_01_ip group_vars/vault.yml | cut -d'"' -f2) "tail -f /opt/monad-consensus/log/monad-consensus.log | grep --line-buffered -E 'round|block|commit|sync|statesync'"

logs: ## View recent logs (last 50 lines)
	@ansible $(INV) validators -m shell -a "tail -50 /opt/monad-consensus/log/monad-consensus.log" -e @group_vars/vault.yml $(VAULT_ARGS)

# Operations
restart: ## Restart monad service
	ansible-playbook $(INV) playbooks/maintenance.yml --tags restart $(VAULT_ARGS)

backup: ## Backup config and keys
	ansible-playbook $(INV) playbooks/maintenance.yml --tags backup $(VAULT_ARGS)

cleanup: ## Cleanup old backups
	ansible-playbook $(INV) playbooks/maintenance.yml --tags cleanup $(VAULT_ARGS)

# Recovery
recovery: ## Full recovery procedure
	ansible-playbook $(INV) playbooks/recovery.yml $(VAULT_ARGS)

diagnose: ## Show diagnostic info (service status, errors)
	ansible-playbook $(INV) playbooks/recovery.yml --tags diagnose $(VAULT_ARGS)

# Utilities
ping: ## Test connectivity to all hosts
	ansible $(INV) all -m ping -e @group_vars/vault.yml $(VAULT_ARGS)

ssh: ## SSH to first validator
	@ssh root@$$(grep vault_validator_01_ip group_vars/vault.yml | cut -d'"' -f2)

check: ## Syntax check playbooks
	ansible-playbook $(INV) playbooks/deploy-validator.yml --syntax-check

# Vault
vault-edit: ## Edit encrypted vault
	ansible-vault edit group_vars/vault.yml

vault-encrypt: ## Encrypt vault file
	ansible-vault encrypt group_vars/vault.yml

vault-decrypt: ## Decrypt vault file
	ansible-vault decrypt group_vars/vault.yml

# ------------------------------------------------------------------------

help: ## Show available targets
	@echo "Monad Validator Manager (ENV=$(ENV))"
	@echo ""
	@echo "Usage: make <target> [ENV=testnet|mainnet]"
	@echo ""
	@awk 'BEGIN {FS=":.*##"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  $(G)%-16s$(N) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
