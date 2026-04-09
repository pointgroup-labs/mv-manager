ENV ?= testnet
INV := inventory/$(ENV).yml
VAULT := group_vars/vault-$(ENV).yml
CLOG := /home/monad/log/monad-consensus.log
ELOG := /home/monad/execution/log/monad-execution.log  # Validator default; fullnodes: monad-fullnode-execution.log
RLOG := /home/monad/log/monad-rpc.log
A := -i $(INV) $(if $(NODE),--limit $(NODE),)

$(if $(wildcard $(INV)),,$(error Inventory not found: $(INV) — valid ENVs: testnet, mainnet))

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

observability: ## Deploy observability stack (Prometheus + Grafana)
	ansible-playbook $(A) playbooks/setup-observability.yml

## Monitoring
health: ## Run health checks
	ansible-playbook $(A) playbooks/maintenance.yml --tags health

status: ## Show validator status [ENV=] [NODE=]
	@MONAD_INV=$(INV) ./scripts/validator-info.sh "$(NODE)"

logs: ## Tail logs [SVC=consensus|execution|rpc] [LINES=50] [NODE=]
	$(eval SVC := $(or $(SVC),consensus))
	$(eval L := $(or $(LINES),50))
	$(eval LOGPATH := $(if $(filter execution,$(SVC)),$(ELOG),$(if $(filter rpc,$(SVC)),$(RLOG),$(CLOG))))
	@ansible $(A) validators:fullnodes -m shell -a 'tail -$(L) $(LOGPATH)' | ./scripts/colorize-logs.sh

watch: ## Stream logs [SVC=consensus|execution|rpc] [NODE=]
	$(eval SVC := $(or $(SVC),consensus))
	$(eval LOGPATH := $(if $(filter execution,$(SVC)),$(ELOG),$(if $(filter rpc,$(SVC)),$(RLOG),$(CLOG))))
	@IP=$$(ansible-inventory $(A) --list 2>/dev/null | jq -r '[._meta.hostvars | to_entries[]] | .[0].value.ansible_host'); \
	ssh root@$$IP 'tail -f $(LOGPATH)' 2>/dev/null | ./scripts/colorize-logs.sh

## Operations
restart: ## Restart services (execution → consensus → rpc)
	ansible-playbook $(A) playbooks/maintenance.yml --tags restart

stop: ## Stop services
	ansible-playbook $(A) playbooks/maintenance.yml --tags stop

start: ## Start services
	ansible-playbook $(A) playbooks/maintenance.yml --tags start

backup: ## Backup keys and config
	ansible-playbook $(A) playbooks/maintenance.yml --tags backup

commission: ## Set commission rate [RATE=20] [NODE=]
	@ansible $(A) validators --become-user monad -m shell -a '/home/monad/scripts/set-commission.sh $(or $(RATE),20)'

claim: ## Claim validator rewards [NODE=]
	@ansible $(A) validators --become-user monad -m shell -a '/home/monad/scripts/claim-rewards.sh'

compound: ## Compound rewards (claim + restake) [NODE=]
	@ansible $(A) validators --become-user monad -m shell -a '/home/monad/scripts/compound-rewards.sh'

## Migration
migrate: ## Fast migrate validator [OLD=name] [NEW=name] (pre-deploy new node first)
	ansible-playbook $(A) playbooks/migrate-validator.yml -e old_node=$(OLD) -e new_node=$(NEW)

## Recovery
recovery: ## Run recovery playbook
	ansible-playbook $(A) playbooks/recovery.yml

diagnose: ## Show diagnostic info
	ansible-playbook $(A) playbooks/recovery.yml --tags diagnose

## Utilities
ping: ## Test connectivity
	@ansible $(A) all -m ping

grafana: ## Open Grafana via SSH tunnel [NODE=]
	@IP=$$(ansible-inventory $(A) --list 2>/dev/null | jq -r '[._meta.hostvars | to_entries[]] | .[0].value.ansible_host'); \
	echo "Grafana: http://localhost:3000"; \
	echo "Press Ctrl+C to close"; \
	ssh -N -L 3000:127.0.0.1:3000 root@$$IP

hardware: ## Show hardware specs (CPU, RAM, storage)
	@MONAD_INV=$(INV) ./scripts/hardware-info.sh "$(NODE)"

speedtest: ## Run bandwidth speedtest
	@MONAD_INV=$(INV) ./scripts/speedtest.sh "$(NODE)"

ssh: ## SSH to first validator
	@ansible-inventory $(A) --list 2>/dev/null | jq -r '.validators.hosts[0] as $$h | .["_meta"]["hostvars"][$$h]["ansible_host"]' | xargs -I{} ssh root@{}

check: ## Syntax check all playbooks
	@for pb in playbooks/*.yml; do \
		printf "  %-40s" "$$pb"; \
		ansible-playbook $(A) $$pb --syntax-check > /dev/null 2>&1 && echo "✓" || echo "✗"; \
	done

## Vault
vault-edit: ## Edit vault secrets [ENV=]
	ansible-vault edit $(VAULT)

vault-encrypt: ## Encrypt vault [ENV=]
	ansible-vault encrypt $(VAULT)

vault-decrypt: ## Decrypt vault [ENV=]
	ansible-vault decrypt $(VAULT)

## Help
help:
	@echo "Usage: make [target] [ENV=testnet|mainnet] [NODE=name]"
	@echo ""
	@echo "  ENV defaults to 'testnet', uses inventory/\$$ENV.yml"
	@echo ""
	@awk '/^## /{sub(/^## /,""); printf "\n\033[1m%s\033[0m\n", $$0; next} \
		/^[a-z-]+:.*##/{split($$0,a,":.*## "); printf "  \033[36m%-12s\033[0m %s\n", a[1], a[2]}' $(MAKEFILE_LIST)
	@echo ""

.DEFAULT_GOAL := help
.PHONY: deploy snapshot execution rpc register upgrade observability health status logs watch restart stop start backup commission claim compound migrate recovery diagnose ping grafana hardware speedtest ssh check vault-edit vault-encrypt vault-decrypt help