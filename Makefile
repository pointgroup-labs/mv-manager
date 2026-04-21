ENV ?= testnet
INV := inventory/$(ENV).yml
VAULT := group_vars/vault-$(ENV).yml
H := /home/monad
CLOG := $(H)/log/monad-consensus.log
VELOG := $(H)/execution/log/monad-execution.log
FELOG := $(H)/execution/log/monad-fullnode-execution.log
RLOG := $(H)/log/monad-rpc.log
A := -i $(INV) $(if $(NODE),--limit $(NODE),)
DR := $(if $(DRYRUN),--check --diff,)

$(if $(wildcard $(INV)),,$(error Inventory not found: $(INV) — valid ENVs: testnet, mainnet))

define confirm
@if [ "$(CONFIRM)" != "yes" ]; then \
	echo "Refusing destructive target '$@'. Re-run with CONFIRM=yes (and DRYRUN=1 if you want --check --diff first)."; \
	exit 1; \
fi
endef

# Resolve a single ansible_host IP: if NODE=name is set, ask inventory about that
# host; else fall back to first host in validators group.
define node_ip
$$(if [ -n "$(NODE)" ]; then \
	ansible-inventory -i $(INV) --host $(NODE) 2>/dev/null | jq -r '.ansible_host // .ansible_ssh_host'; \
else \
	ansible-inventory -i $(INV) --list 2>/dev/null | jq -r '.validators.hosts[0] as $$h | .["_meta"]["hostvars"][$$h]["ansible_host"]'; \
fi)
endef

# Resolve node type (validator|fullnode) so log commands pick the right exec log.
define node_type
$$(if [ -n "$(NODE)" ]; then \
	ansible-inventory -i $(INV) --host $(NODE) 2>/dev/null | jq -r '.type // "validator"'; \
else \
	echo validator; \
fi)
endef

## Deployment
bootstrap: ## Bootstrap new validator: generate keys + vault [NAME=foo-testnet]
	$(if $(NAME),,$(error NAME= required, e.g. NAME=kiwi-testnet))
	@NAME=$(NAME) $(if $(filter command\ line environment,$(origin ENV)),ENV=$(ENV),) ./scripts/bootstrap.sh

deploy: ## Deploy validator
	ansible-playbook $(A) $(DR) playbooks/deploy-validator.yml

snapshot: ## Apply snapshot for fast sync
	ansible-playbook $(A) $(DR) playbooks/snapshot.yml

execution: ## Setup execution layer
	ansible-playbook $(A) $(DR) playbooks/setup-execution.yml

rpc: ## Setup JSON-RPC server
	ansible-playbook $(A) $(DR) playbooks/setup-rpc.yml

register: ## Register validator (requires synced node + 100k MON)
	ansible-playbook $(A) $(DR) playbooks/register-validator.yml

upgrade: ## Upgrade monad packages (destructive; requires CONFIRM=yes)
	$(call confirm)
	ansible-playbook $(A) $(DR) playbooks/upgrade-node.yml

observability: ## Deploy observability stack (Prometheus + Grafana)
	ansible-playbook $(A) $(DR) playbooks/setup-observability.yml

## Monitoring
status: ## Show validator status [ENV=] [NODE=]
	@MONAD_INV=$(INV) ./scripts/validator-info.sh "$(NODE)"

health: ## Run health checks
	ansible-playbook $(A) playbooks/maintenance.yml --tags health

logs: ## Tail logs [SVC=consensus|execution|rpc] [LINES=50] [NODE=]
	$(eval SVC := $(or $(SVC),consensus))
	$(eval L := $(or $(LINES),50))
	@TYPE=$(call node_type); \
	EXEC_LOG=$$([ "$$TYPE" = "fullnode" ] && echo "$(FELOG)" || echo "$(VELOG)"); \
	case "$(SVC)" in \
		execution) LOGPATH=$$EXEC_LOG ;; \
		rpc) LOGPATH="$(RLOG)" ;; \
		*) LOGPATH="$(CLOG)" ;; \
	esac; \
	ansible $(A) validators:fullnodes -m shell -a "tail -$(L) $$LOGPATH" | ./scripts/colorize-logs.sh

watch: ## Stream logs [SVC=consensus|execution|rpc] [NODE=]
	$(eval SVC := $(or $(SVC),consensus))
	@IP=$(call node_ip); \
	TYPE=$(call node_type); \
	EXEC_LOG=$$([ "$$TYPE" = "fullnode" ] && echo "$(FELOG)" || echo "$(VELOG)"); \
	case "$(SVC)" in \
		execution) LOGPATH=$$EXEC_LOG ;; \
		rpc) LOGPATH="$(RLOG)" ;; \
		*) LOGPATH="$(CLOG)" ;; \
	esac; \
	ssh root@$$IP "tail -f $$LOGPATH" 2>/dev/null | ./scripts/colorize-logs.sh

## Operations
restart: ## Restart services (execution → consensus → rpc)
	ansible-playbook $(A) $(DR) playbooks/maintenance.yml --tags restart

stop: ## Stop services (destructive; requires CONFIRM=yes)
	$(call confirm)
	ansible-playbook $(A) $(DR) playbooks/maintenance.yml --tags stop

start: ## Start services
	ansible-playbook $(A) $(DR) playbooks/maintenance.yml --tags start

commission: ## Set commission rate [RATE=20] [NODE=]
	@ansible $(A) validators -b --become-user monad -m shell -a '$(H)/scripts/set-commission.sh $(or $(RATE),20)'

claim: ## Claim validator rewards [NODE=]
	@ansible $(A) validators -b --become-user monad -m shell -a '$(H)/scripts/claim-rewards.sh'

compound: ## Compound rewards (claim + restake) [NODE=]
	@ansible $(A) validators -b --become-user monad -m shell -a '$(H)/scripts/compound-rewards.sh'

auto-compound: ## Enable auto-compound timer [SCHEDULE="0 8 * * *"] [NODE=]
	ansible-playbook $(A) playbooks/maintenance.yml --tags auto-compound \
		$(if $(SCHEDULE),-e compound_rewards_schedule="$(SCHEDULE)",) \
		-e compound_rewards_enabled=true

## Backup
backup-config: ## Backup config on remote server [NODE=]
	ansible-playbook $(A) playbooks/maintenance.yml --tags backup

backup-keys: ## Download validator keystores to secrets/ [NODE=]
	@ansible $(A) validators -b --become-user monad -m fetch \
		-a 'src=$(H)/key/id-secp dest=secrets/{{ inventory_hostname }}-id-secp flat=yes'
	@ansible $(A) validators -b --become-user monad -m fetch \
		-a 'src=$(H)/key/id-bls dest=secrets/{{ inventory_hostname }}-id-bls flat=yes'
	@echo "" && echo "Keys saved to secrets/"

## Migration
migrate: ## Fast migrate validator [OLD=name] [NEW=name] (pre-deploy new node first)
	$(if $(OLD),,$(error OLD= required (source node name)))
	$(if $(NEW),,$(error NEW= required (destination node name)))
	ansible-playbook $(A) $(DR) playbooks/migrate-validator.yml -e old_node=$(OLD) -e new_node=$(NEW)

## MEV
fastlane: ## Deploy FastLane sidecar [NODE=]
	ansible-playbook $(A) $(DR) playbooks/setup-fastlane.yml

sidecar-health: ## Check sidecar health [NODE=]
	@ansible $(A) validators -m shell -a 'curl -s http://localhost:8765/health | jq' 2>/dev/null | ./scripts/colorize-logs.sh

## Recovery
recovery: ## Run recovery playbook (destructive; requires CONFIRM=yes)
	$(call confirm)
	ansible-playbook $(A) $(DR) playbooks/recovery.yml

diagnose: ## Show diagnostic info
	ansible-playbook $(A) playbooks/recovery.yml --tags diagnose

## Utilities
ping: ## Test connectivity
	@ansible $(A) all -m ping

grafana: ## Open Grafana via SSH tunnel [NODE=]
	@IP=$(call node_ip); \
	echo "Grafana: http://localhost:3000"; \
	echo "Press Ctrl+C to close"; \
	ssh -N -L 3000:127.0.0.1:3000 root@$$IP

hardware: ## Show hardware specs (CPU, RAM, storage)
	@MONAD_INV=$(INV) ./scripts/hardware-info.sh "$(NODE)"

speedtest: ## Run bandwidth speedtest
	@MONAD_INV=$(INV) ./scripts/speedtest.sh "$(NODE)"

ssh: ## SSH to validator [NODE=]
	@IP=$(call node_ip); ssh root@$$IP

check: ## Syntax check all playbooks
	@rc=0; \
	for pb in playbooks/*.yml; do \
		printf "  %-40s" "$$pb"; \
		if ansible-playbook $(A) $$pb --syntax-check > /dev/null; then \
			echo "✓"; \
		else \
			echo "✗"; rc=1; \
		fi; \
	done; \
	exit $$rc

## Vault
vault-edit: ## Edit vault secrets [ENV=]
	ansible-vault edit $(VAULT)

vault-encrypt: ## Encrypt vault [ENV=]
	ansible-vault encrypt $(VAULT)

vault-decrypt: ## Decrypt vault [ENV=]
	ansible-vault decrypt $(VAULT)

## Help
help:
	@echo "Usage: make [target] [ENV=testnet|mainnet] [NODE=name] [DRYRUN=1] [CONFIRM=yes]"
	@echo ""
	@echo "  ENV defaults to 'testnet', uses inventory/\$$ENV.yml"
	@echo "  DRYRUN=1 passes --check --diff to ansible-playbook"
	@echo "  CONFIRM=yes required for destructive targets: upgrade, stop, recovery"
	@echo ""
	@awk '/^## /{sub(/^## /,""); printf "\n\033[1m%s\033[0m\n", $$0; next} \
		/^[a-z-]+:.*##/{split($$0,a,":.*## "); printf "  \033[36m%-12s\033[0m %s\n", a[1], a[2]}' $(MAKEFILE_LIST)
	@echo ""

.DEFAULT_GOAL := help
.PHONY: bootstrap deploy snapshot execution rpc register upgrade observability fastlane sidecar-health status health logs watch restart stop start commission claim compound auto-compound backup-config backup-keys migrate recovery diagnose ping grafana hardware speedtest ssh check vault-edit vault-encrypt vault-decrypt help
