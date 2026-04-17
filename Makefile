SHELL := /bin/bash

ENV ?= dev
ENV_FILE ?= env/.env.$(ENV)

ENV_CUSTOM_IMAGE := $(strip $(shell [ -f "$(ENV_FILE)" ] && sed -n 's/^CUSTOM_IMAGE=//p' "$(ENV_FILE)" | tail -n1))
ENV_CUSTOM_TAG := $(strip $(shell [ -f "$(ENV_FILE)" ] && sed -n 's/^CUSTOM_TAG=//p' "$(ENV_FILE)" | tail -n1))

CUSTOM_IMAGE ?= $(if $(ENV_CUSTOM_IMAGE),$(ENV_CUSTOM_IMAGE),icwinner/erpnext-designers)
CUSTOM_TAG ?= $(if $(ENV_CUSTOM_TAG),$(ENV_CUSTOM_TAG),v16-dev-001)
FRAPPE_PATH ?= https://github.com/frappe/frappe
FRAPPE_BRANCH ?= version-16
ERPNEXT_PATH ?= https://github.com/frappe/erpnext
ERPNEXT_BRANCH ?= version-16
APPS_JSON_BENCH ?= /Users/dmitriy/Projects/work/erp/frappe_docker/apps.json
NO_CACHE ?= 1
PLATFORM ?= linux/amd64

ENV_OVERRIDE ?= overrides/compose.$(ENV).yaml
COMPOSE_ENV = docker compose --env-file $(ENV_FILE) -f compose.yaml -f overrides/compose.mariadb.yaml -f overrides/compose.redis.yaml -f $(ENV_OVERRIDE)
EXPORT_APP ?= designers
EXPORT_HOST_APP_PATH ?= /Users/dmitriy/Projects/work/erp/myerp/frapper-bench/apps/designers
LOCAL_DESIGNERS_APP_PATH ?= /Users/dmitriy/Projects/work/erp/myerp/frapper-bench/apps/designers

SITE_PROD ?= ecklet
REMOTE_HOST ?= root@your-server
REMOTE_DIR ?= /opt/frappe_docker

.PHONY: help env-up env-down env-logs env-ps env-sync-assets env-import-all env-export-all build-image-from-bench push-image release deploy-prod-script deploy-remote

help:
	@echo "Targets:"
	@echo "  make ENV=dev env-up         - Поднять dev окружение (локальный designers bind mount) и синхронизировать assets"
	@echo "  make ENV=dev env-down       - Остановить окружение"
	@echo "  make ENV=dev env-logs       - Логи окружения"
	@echo "  make ENV=dev env-ps         - Статус контейнеров"
	@echo "  make ENV=dev env-sync-assets- Принудительно синхронизировать assets backend -> frontend"
	@echo "  make ENV=dev env-import-all - Применить весь код в сайт (migrate + clear-cache + sync assets)"
	@echo "  make ENV=dev env-export-all - Выгрузить изменения из UI в код (fixtures)"
	@echo "  make build-image-from-bench - Собрать образ из apps.json"
	@echo "  make push-image             - Запушить образ $(CUSTOM_IMAGE):$(CUSTOM_TAG)"
	@echo "  make release                - build-image-from-bench + push-image"
	@echo "  make deploy-prod-script     - pull/up/migrate/clear-cache через scripts/deploy-prod.sh"
	@echo "  make deploy-remote          - Выполнить deploy-prod-script на удаленном сервере"

env-up:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE)"; exit 1)
	@test -f "$(ENV_OVERRIDE)" || (echo "Missing $(ENV_OVERRIDE)"; exit 1)
	@if [ "$(ENV)" = "dev" ]; then test -d "$(LOCAL_DESIGNERS_APP_PATH)" || (echo "Missing LOCAL_DESIGNERS_APP_PATH: $(LOCAL_DESIGNERS_APP_PATH)"; exit 1); fi
	$(COMPOSE_ENV) up -d
	$(MAKE) ENV=$(ENV) env-sync-assets

env-down:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE)"; exit 1)
	@test -f "$(ENV_OVERRIDE)" || (echo "Missing $(ENV_OVERRIDE)"; exit 1)
	$(COMPOSE_ENV) down

env-logs:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE)"; exit 1)
	@test -f "$(ENV_OVERRIDE)" || (echo "Missing $(ENV_OVERRIDE)"; exit 1)
	$(COMPOSE_ENV) logs -f --tail=200

env-ps:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE)"; exit 1)
	@test -f "$(ENV_OVERRIDE)" || (echo "Missing $(ENV_OVERRIDE)"; exit 1)
	$(COMPOSE_ENV) ps

env-sync-assets:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE)"; exit 1)
	@test -f "$(ENV_OVERRIDE)" || (echo "Missing $(ENV_OVERRIDE)"; exit 1)
	@set -e; \
	backend_cid="$$($(COMPOSE_ENV) ps -q backend)"; \
	frontend_cid="$$($(COMPOSE_ENV) ps -q frontend)"; \
	if [ -z "$$backend_cid" ] || [ -z "$$frontend_cid" ]; then \
		echo "Skip env-sync-assets: backend/frontend container not found"; \
		exit 0; \
	fi; \
	$(COMPOSE_ENV) exec -T backend bench build; \
	tmp_dir="$$(mktemp -d /tmp/frappe-assets-sync.XXXXXX)"; \
	mkdir -p "$$tmp_dir/frappe-dist" "$$tmp_dir/erpnext-dist"; \
	docker cp "$$backend_cid:/home/frappe/frappe-bench/sites/assets/frappe/dist/." "$$tmp_dir/frappe-dist"; \
	docker cp "$$backend_cid:/home/frappe/frappe-bench/sites/assets/erpnext/dist/." "$$tmp_dir/erpnext-dist"; \
	docker cp "$$backend_cid:/home/frappe/frappe-bench/sites/assets/assets.json" "$$tmp_dir/assets.json"; \
	$(COMPOSE_ENV) exec -T -u root frontend bash -lc "mkdir -p /home/frappe/frappe-bench/sites/assets/frappe/dist /home/frappe/frappe-bench/sites/assets/erpnext/dist && rm -rf /home/frappe/frappe-bench/sites/assets/frappe/dist/* /home/frappe/frappe-bench/sites/assets/erpnext/dist/*"; \
	docker cp "$$tmp_dir/frappe-dist/." "$$frontend_cid:/home/frappe/frappe-bench/sites/assets/frappe/dist"; \
	docker cp "$$tmp_dir/erpnext-dist/." "$$frontend_cid:/home/frappe/frappe-bench/sites/assets/erpnext/dist"; \
	docker cp "$$tmp_dir/assets.json" "$$frontend_cid:/home/frappe/frappe-bench/sites/assets/assets.json"; \
	$(COMPOSE_ENV) exec -T -u root frontend bash -lc "chown -R frappe:frappe /home/frappe/frappe-bench/sites/assets/frappe/dist /home/frappe/frappe-bench/sites/assets/erpnext/dist /home/frappe/frappe-bench/sites/assets/assets.json"; \
	site_name="$$(grep -E '^BOOTSTRAP_SITE_NAME=' $(ENV_FILE) | tail -n1 | cut -d= -f2- | tr -d '\"')"; \
	if [ -n "$$site_name" ]; then \
		$(COMPOSE_ENV) exec -T backend bench --site "$$site_name" clear-cache || true; \
		$(COMPOSE_ENV) exec -T backend bench --site "$$site_name" clear-website-cache || true; \
	fi; \
	$(COMPOSE_ENV) restart backend websocket frontend >/dev/null; \
	rm -rf "$$tmp_dir"; \
	echo "Assets rebuilt, synced, and services restarted"

env-import-all:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE)"; exit 1)
	@test -f "$(ENV_OVERRIDE)" || (echo "Missing $(ENV_OVERRIDE)"; exit 1)
	@site_name="$$(grep -E '^BOOTSTRAP_SITE_NAME=' $(ENV_FILE) | tail -n1 | cut -d= -f2- | tr -d '"')"; \
	if [ -z "$$site_name" ]; then \
		echo "BOOTSTRAP_SITE_NAME is empty in $(ENV_FILE)"; \
		exit 1; \
	fi; \
	$(COMPOSE_ENV) exec -T backend bench --site "$$site_name" migrate; \
	$(COMPOSE_ENV) exec -T backend bench --site "$$site_name" clear-cache; \
	$(MAKE) ENV=$(ENV) env-sync-assets

env-export-all:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE)"; exit 1)
	@test -f "$(ENV_OVERRIDE)" || (echo "Missing $(ENV_OVERRIDE)"; exit 1)
	@test -d "$(EXPORT_HOST_APP_PATH)" || (echo "Missing EXPORT_HOST_APP_PATH: $(EXPORT_HOST_APP_PATH)"; exit 1)
	@set -e; \
	site_name="$$(grep -E '^BOOTSTRAP_SITE_NAME=' $(ENV_FILE) | tail -n1 | cut -d= -f2- | tr -d '"')"; \
	if [ -z "$$site_name" ]; then \
		echo "BOOTSTRAP_SITE_NAME is empty in $(ENV_FILE)"; \
		exit 1; \
	fi; \
	backend_cid="$$($(COMPOSE_ENV) ps -q backend)"; \
	if [ -z "$$backend_cid" ]; then \
		echo "Backend container not found"; \
		exit 1; \
	fi; \
	$(COMPOSE_ENV) exec -T backend bench --site "$$site_name" export-fixtures; \
	tmp_dir="$$(mktemp -d /tmp/frappe-export.XXXXXX)"; \
	mkdir -p "$$tmp_dir/fixtures"; \
	docker cp "$$backend_cid:/home/frappe/frappe-bench/apps/$(EXPORT_APP)/$(EXPORT_APP)/fixtures/." "$$tmp_dir/fixtures"; \
	mkdir -p "$(EXPORT_HOST_APP_PATH)/$(EXPORT_APP)/fixtures"; \
	rm -rf "$(EXPORT_HOST_APP_PATH)/$(EXPORT_APP)/fixtures/"*; \
	cp -R "$$tmp_dir/fixtures/." "$(EXPORT_HOST_APP_PATH)/$(EXPORT_APP)/fixtures/"; \
	rm -rf "$$tmp_dir"; \
	echo "Exported fixtures -> $(EXPORT_HOST_APP_PATH)/$(EXPORT_APP)/fixtures"

build-image-from-bench:
	@test -f "$(APPS_JSON_BENCH)" || (echo "Ошибка: не найден файл $(APPS_JSON_BENCH)"; exit 1)
	@jq -e 'type=="array" and all(.[]; .url and (.url|type=="string") and (.url|length>0))' "$(APPS_JSON_BENCH)" >/dev/null || (echo "Ошибка: $(APPS_JSON_BENCH) должен быть JSON-массивом объектов с полем url"; exit 1)
	@APPS_JSON_BASE64=$$(base64 < $(APPS_JSON_BENCH) | tr -d '\n'); \
	docker build \
	  $$( [ "$(NO_CACHE)" = "1" ] && echo "--no-cache --pull" ) \
	  --build-arg APPS_JSON_BASE64=$$APPS_JSON_BASE64 \
	  --build-arg FRAPPE_PATH=$(FRAPPE_PATH) \
	  --build-arg FRAPPE_BRANCH=$(FRAPPE_BRANCH) \
	  --build-arg ERPNEXT_PATH=$(ERPNEXT_PATH) \
	  --build-arg ERPNEXT_BRANCH=$(ERPNEXT_BRANCH) \
	  --platform $(PLATFORM) \
	  --tag $(CUSTOM_IMAGE):$(CUSTOM_TAG) \
	  -f images/custom/Containerfile .

push-image:
	docker push $(CUSTOM_IMAGE):$(CUSTOM_TAG)

release: build-image-from-bench push-image

deploy-prod-script:
	./scripts/deploy-prod.sh env/.env.prod $(SITE_PROD)

deploy-remote:
	ssh $(REMOTE_HOST) "cd $(REMOTE_DIR) && make deploy-prod-script"
