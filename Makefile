INV := inventory/local.yml
CLOG := /home/monad/log/monad-consensus.log
ELOG := /home/monad/execution/log/monad-execution.log
RLOG := /home/monad/log/monad-rpc.log
A := -i $(INV) $(if $(NODE),--limit $(NODE),)

## Deployment
deploy: ## Deploy validator
	ansible-playbook $(A) playbooks/deploy-validator.yml

snapshot: ## Apply snapshot for fast sync
	ansible-playbook $(A) playbooks/snapshot.yml

execution: ## Setup execution layer
	ansible-playbook $(A) playbooks/setup-execution.yml

rpc: ## Setup JSON-RPC server
	ansible-playbook $(A) playbooks/setup-rpc.yml

register: ## Register validator (requires synced node + 100k MON)
	ansible-playbook $(A) playbooks/register-validator.yml

upgrade: ## Upgrade monad packages
	ansible-playbook $(A) playbooks/upgrade-node.yml

## Monitoring
health: ## Run health checks
	ansible-playbook $(A) playbooks/maintenance.yml --tags health

status: ## Show validator status [NODE=]
	@./scripts/validator-info.sh "$(NODE)"

logs: ## Tail logs [SVC=consensus|execution|rpc] [LINES=50] [NODE=]
	$(eval SVC := $(or $(SVC),consensus))
	$(eval L := $(or $(LINES),50))
	$(eval LOGPATH := $(if $(filter execution,$(SVC)),$(ELOG),$(if $(filter rpc,$(SVC)),$(RLOG),$(CLOG))))
	@ansible $(A) validators -m shell -a 'tail -$(L) $(LOGPATH)' | ./scripts/colorize-logs.sh

watch: ## Stream logs [SVC=consensus|execution|rpc] [NODE=]
	$(eval SVC := $(or $(SVC),consensus))
	$(eval LOGPATH := $(if $(filter execution,$(SVC)),$(ELOG),$(if $(filter rpc,$(SVC)),$(RLOG),$(CLOG))))
	@IP=$$(ansible-inventory $(A) --list 2>/dev/null | jq -r '[._meta.hostvars | to_entries[] | select(.value.type=="validator")] | .[0].value.ansible_host'); \
	ssh root@$$IP 'tail -f $(LOGPATH)' 2>/dev/null | ./scripts/colorize-logs.sh

## Operations
restart: ## Restart services (execution → consensus → rpc)
	@ansible $(A) validators -m shell -a 'systemctl restart monad-execution && sleep 3 && systemctl restart monad-consensus && sleep 2 && systemctl restart monad-rpc'

stop: ## Stop services
	@ansible $(A) validators -m shell -a 'systemctl stop monad-rpc monad-consensus monad-execution'

start: ## Start services
	@ansible $(A) validators -m shell -a 'systemctl start monad-execution && sleep 2 && systemctl start monad-consensus && sleep 2 && systemctl start monad-rpc'

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

hardware: ## Show hardware specs (CPU, RAM, storage)
	@./scripts/hardware-info.sh "$(NODE)"

speedtest: ## Run bandwidth speedtest
	@./scripts/speedtest.sh "$(NODE)"

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
.PHONY: deploy snapshot execution rpc register upgrade health status logs watch restart stop start backup recovery diagnose ping hardware speedtest ssh check vault-edit vault-encrypt vault-decrypt help