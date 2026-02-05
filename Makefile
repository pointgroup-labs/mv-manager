INV := inventory/local.yml
LOG := /opt/monad-consensus/log/monad-consensus.log
A := -i $(INV) $(if $(NODE),--limit $(NODE),)

## Deployment
deploy: ## Deploy validator
	ansible-playbook $(A) playbooks/deploy-validator.yml

snapshot: ## Apply snapshot for fast sync
	ansible-playbook $(A) playbooks/snapshot.yml

execution: ## Setup execution layer
	ansible-playbook $(A) playbooks/setup-execution.yml

register: ## Register validator (requires synced node + 100k MON)
	ansible-playbook $(A) playbooks/register-validator.yml

upgrade: ## Upgrade monad packages
	ansible-playbook $(A) playbooks/upgrade-node.yml

## Monitoring
health: ## Run health checks
	ansible-playbook $(A) playbooks/maintenance.yml --tags health

status: ## Show validator status [NODE=]
	@./scripts/validator-info.sh "$(NODE)"

sync: ## Show current block number
	@ansible $(A) validators -m shell -a '\
		grep "\"committed block\"" $(LOG) 2>/dev/null | \
		tail -1 | sed "s/.*block_num\"://; s/},.*//" || echo "No blocks yet"' 2>/dev/null | grep -v "CHANGED\|SUCCESS" || true

logs: ## Tail consensus logs (LINES=100)
	@ansible $(A) validators -m shell -a '\
		tail -$(or $(LINES),100) $(LOG) | \
		grep -E "INFO|WARN|ERROR" | tail -20'

watch: ## Stream logs in real-time
	@IP=$$(ansible-inventory $(A) --list 2>/dev/null | jq -r '.validators.hosts[0] as $$h | .["_meta"]["hostvars"][$$h]["ansible_host"]'); \
	ssh root@$$IP 'tail -f $(LOG)' 2>/dev/null | ./scripts/colorize-logs.sh

## Operations
restart: ## Restart services
	@ansible $(A) validators -m shell -a 'systemctl restart monad-consensus'

stop: ## Stop services
	@ansible $(A) validators -m shell -a 'systemctl stop monad-consensus monad-execution'

start: ## Start services
	@ansible $(A) validators -m shell -a 'systemctl start monad-execution && sleep 2 && systemctl start monad-consensus'

backup: ## Backup keys and config
	ansible-playbook $(A) playbooks/maintenance.yml --tags backup

## Recovery
recovery: ## Run recovery playbook
	ansible-playbook $(A) playbooks/recovery.yml

diagnose: ## Show diagnostic info
	ansible-playbook $(A) playbooks/recovery.yml --tags diagnose

## Utilities
ping: ## Test connectivity
	@ansible $(A) all -m ping

ssh: ## SSH to first validator
	@ansible-inventory $(A) --list 2>/dev/null | jq -r '.validators.hosts[0] as $$h | .["_meta"]["hostvars"][$$h]["ansible_host"]' | xargs -I{} ssh root@{}

check: ## Syntax check playbooks
	@ansible-playbook $(A) playbooks/deploy-validator.yml --syntax-check

## Vault
vault-edit: ## Edit vault secrets
	ansible-vault edit group_vars/vault.yml

vault-encrypt: ## Encrypt vault
	ansible-vault encrypt group_vars/vault.yml

vault-decrypt: ## Decrypt vault
	ansible-vault decrypt group_vars/vault.yml

## Help
help:
	@echo "Usage: make [target] [NODE=name]"
	@echo ""
	@awk '/^## /{sub(/^## /,""); printf "\n\033[1m%s\033[0m\n", $$0; next} \
		/^[a-z-]+:.*##/{split($$0,a,":.*## "); printf "  \033[36m%-12s\033[0m %s\n", a[1], a[2]}' $(MAKEFILE_LIST)
	@echo ""

.DEFAULT_GOAL := help
.PHONY: deploy snapshot execution register upgrade health status sync logs watch restart stop start backup recovery diagnose ping ssh check vault-edit vault-encrypt vault-decrypt help