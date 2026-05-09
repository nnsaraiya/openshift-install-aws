.DEFAULT_GOAL := help
# Resolve ansible binaries — handles system PATH and pip --user installs on macOS and Linux
_OS := $(shell uname -s)
ifeq ($(_OS),Darwin)
  _PY_USER_BIN := $(HOME)/Library/Python/$(shell python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo 3.10)/bin
else
  _PY_USER_BIN := $(HOME)/.local/bin
endif
ANSIBLE_BIN   := $(shell command -v ansible-playbook 2>/dev/null || echo $(_PY_USER_BIN)/ansible-playbook)
GALAXY_BIN    := $(shell command -v ansible-galaxy  2>/dev/null || echo $(_PY_USER_BIN)/ansible-galaxy)
VAULT_BIN     := $(shell command -v ansible-vault   2>/dev/null || echo $(_PY_USER_BIN)/ansible-vault)
ANSIBLE       := $(ANSIBLE_BIN) -i inventory/hosts

.PHONY: help setup encrypt-vault decrypt-vault validate install destroy day2

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

setup: ## Install Ansible collections from requirements.yml
	$(GALAXY_BIN) collection install -r requirements.yml

encrypt-vault: ## Encrypt the vault file (first time setup)
	$(VAULT_BIN) encrypt inventory/group_vars/all/vault.yml

decrypt-vault: ## Decrypt the vault file for editing
	$(VAULT_BIN) decrypt inventory/group_vars/all/vault.yml

edit-vault: ## Open the vault file in your editor
	$(VAULT_BIN) edit inventory/group_vars/all/vault.yml

validate: ## Validate AWS credentials, Route53, and prerequisites (no cluster created)
	$(ANSIBLE) playbooks/validate.yml

install: ## Install cluster only (run 'make day2' separately for Day 2 config)
	$(ANSIBLE) playbooks/install.yml --skip-tags day2

install-with-day2: ## Install cluster AND apply Day 2 config in one shot
	$(ANSIBLE) playbooks/install.yml

day2: ## Apply Day 2 config to an existing cluster (htpasswd, registry, kubeadmin removal)
	$(ANSIBLE) playbooks/day2/configure.yml

destroy: ## DESTROY the cluster and all AWS resources (irreversible!)
	$(ANSIBLE) playbooks/destroy.yml
