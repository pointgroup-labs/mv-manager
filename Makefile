VAULT_ARGS ?=
.DEFAULT_GOAL := help
G := \033[32m
N := \033[0m

.PHONY: deploy register upgrade health status sync logs restart backup cleanup recovery diagnose ping ssh check vault-edit vault-encrypt vault-decrypt help

# Deployment
deploy: ## Full validator deployment
	ansible-playbook playbooks/deploy-validator.yml $(VAULT_ARGS)

register: ## Register validator (requires synced node + 100k MON)
	ansible-playbook playbooks/register-validator.yml $(VAULT_ARGS)

upgrade: ## Upgrade monad packages
	ansible-playbook playbooks/upgrade-node.yml $(VAULT_ARGS)

# Monitoring
health: ## Run health checks
	ansible-playbook playbooks/maintenance.yml --tags health $(VAULT_ARGS)

status: ## Show service status and disk usage
	ansible-playbook playbooks/maintenance.yml --tags status $(VAULT_ARGS)

sync: ## Check node sync progress
	ansible-playbook playbooks/maintenance.yml --tags sync $(VAULT_ARGS)

logs: ## View recent logs (last 50 lines)
	@ansible validators -m shell -a "tail -50 /opt/monad-consensus/log/monad-consensus.log" -e @group_vars/vault.yml $(VAULT_ARGS)

watch: ## Watch sync progress in real-time
	@ssh root@$$(ansible-inventory --list -e @group_vars/vault.yml 2>/dev/null | jq -r '._meta.hostvars | to_entries[0].value.ansible_host') "tail -f /opt/monad-consensus/log/monad-consensus.log | grep --line-buffered -E 'round|block|commit|sync|statesync'"

# Operations
restart: ## Restart monad service
	ansible-playbook playbooks/maintenance.yml --tags restart $(VAULT_ARGS)

backup: ## Backup config and keys
	ansible-playbook playbooks/maintenance.yml --tags backup $(VAULT_ARGS)

cleanup: ## Cleanup old backups
	ansible-playbook playbooks/maintenance.yml --tags cleanup $(VAULT_ARGS)

# Recovery
recovery: ## Full recovery procedure
	ansible-playbook playbooks/recovery.yml $(VAULT_ARGS)

diagnose: ## Show diagnostic info (service status, errors)
	ansible-playbook playbooks/recovery.yml --tags diagnose $(VAULT_ARGS)

# Utilities
ping: ## Test connectivity to all hosts
	ansible all -m ping -e @group_vars/vault.yml $(VAULT_ARGS)

ssh: ## SSH to first validator
	@ansible-inventory --list -e @group_vars/vault.yml $(VAULT_ARGS) 2>/dev/null | jq -r '.validators.hosts[0]' | xargs -I{} ssh root@{}

check: ## Syntax check playbooks
	ansible-playbook playbooks/deploy-validator.yml --syntax-check

# Vault
vault-edit: ## Edit encrypted vault
	ansible-vault edit group_vars/vault.yml

vault-encrypt: ## Encrypt vault file
	ansible-vault encrypt group_vars/vault.yml

vault-decrypt: ## Decrypt vault file
	ansible-vault decrypt group_vars/vault.yml

# Help
help: ## Show available targets
	@echo "Monad Validator - Ansible Automation"
	@echo ""
	@awk 'BEGIN {FS=":.*##"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  $(G)%-16s$(N) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
