SHELL := /bin/bash

SITE_DEV ?= ecklet
SITE_PROD ?= ecklet-prod
BACKEND_CONTAINER ?= frappe_docker-backend-1
SITE ?= ecklet
CUSTOM_IMAGE ?= myerp/erpnext-designers
CUSTOM_TAG ?= v16
FRAPPE_PATH ?= https://github.com/frappe/frappe
FRAPPE_BRANCH ?= version-16
ERPNEXT_PATH ?= https://github.com/frappe/erpnext
ERPNEXT_BRANCH ?= version-16
APPS_JSON_BENCH ?= /Users/dmitriy/Projects/work/erp/frappe_docker/apps.json
REMOTE_HOST ?= root@your-server
REMOTE_DIR ?= /opt/frappe_docker
DOCNAME ?=
NO_CACHE ?= 1

COMPOSE_BASE = docker compose -f compose.yaml -f overrides/compose.mariadb.yaml -f overrides/compose.redis.yaml
COMPOSE_DEV = $(COMPOSE_BASE) -f overrides/compose.dev-designers.yaml

.PHONY: help dev-up dev-down dev-logs dev-shell migrate-dev clear-dev build-designers build-designer clear-cache build-assets-dev-backend build-assets-dev-frontend sync-assets-dev-frontend build-assets-dev refresh-ui-dev export-doctype-dev export-all-dev export-ui-dev prod-up prod-down prod-logs migrate-prod clear-prod list-apps-prod build-image-from-bench up-with-built-image push-image release deploy-remote

help:
	@echo "Targets:"
	@echo "  make dev-up               - Запустить dev-стек с bind-mount designers"
	@echo "  make dev-down             - Остановить dev-стек"
	@echo "  make dev-logs             - Показать логи dev в реальном времени"
	@echo "  make dev-shell            - Открыть shell backend в dev-стеке"
	@echo "  make migrate-dev          - Выполнить migrate для SITE_DEV (по умолчанию: ecklet)"
	@echo "  make clear-dev            - Очистить кэш для SITE_DEV"
	@echo "  make build-assets-dev-backend  - Пересобрать assets в backend контейнере"
	@echo "  make build-assets-dev-frontend - Пересобрать assets в frontend контейнере"
	@echo "  make sync-assets-dev-frontend - Синхронизировать assets из backend в frontend"
	@echo "  make build-assets-dev     - Пересобрать assets в backend, синхронизировать во frontend"
	@echo "  make refresh-ui-dev       - Полный цикл фикса UI (migrate + build-assets + clear-cache)"
	@echo "  make export-doctype-dev   - Экспортировать DocType из UI в код (DOCNAME=<Имя DocType>)"
	@echo "  make export-all-dev       - Экспортировать все fixtures из UI в код (hooks.py fixtures)"
	@echo "  make export-ui-dev        - Экспортировать максимум UI-изменений в код (fixtures + DocType/Web Form/Workspace)"
	@echo "  make build-image-from-bench - Собрать образ из apps.json в bench-frappe"
	@echo "  make up-with-built-image  - Поднять контейнеры с CUSTOM_IMAGE:CUSTOM_TAG"
	@echo "  make push-image           - Отправить образ $(CUSTOM_IMAGE):$(CUSTOM_TAG) в registry"
	@echo "  make release              - build-image-from-bench + push-image"
	@echo "  make prod-up              - Запустить prod-стек (без bind-mount)"
	@echo "  make prod-down            - Остановить prod-стек"
	@echo "  make prod-logs            - Показать логи prod в реальном времени"
	@echo "  make migrate-prod         - Выполнить migrate для SITE_PROD (по умолчанию: ecklet-prod)"
	@echo "  make clear-prod           - Очистить кэш для SITE_PROD"
	@echo "  make list-apps-prod       - Показать список приложений на SITE_PROD"
	@echo "  make deploy-remote        - Деплой образа на удаленный сервер по SSH"

dev-up:
	$(COMPOSE_DEV) up -d

dev-down:
	$(COMPOSE_DEV) down

dev-logs:
	$(COMPOSE_DEV) logs -f --tail=200

dev-shell:
	$(COMPOSE_DEV) exec backend bash

migrate-dev:
	$(COMPOSE_DEV) exec backend bench --site $(SITE_DEV) migrate


clear-dev:
	$(COMPOSE_DEV) exec backend bench --site $(SITE_DEV) clear-cache

build-designers:
	docker exec $(BACKEND_CONTAINER) bench build --app designers

build-designer: build-designers

clear-cache:
	docker exec $(BACKEND_CONTAINER) bench --site $(SITE) clear-cache

build-assets-dev-backend:
	$(COMPOSE_DEV) exec -T backend bench build --apps frappe,erpnext,designers

build-assets-dev-frontend:
	$(COMPOSE_DEV) exec -T frontend bench build --apps frappe,erpnext,designers
	$(COMPOSE_DEV) exec -T frontend python -c "import glob,json,os; p='/home/frappe/frappe-bench/sites/assets/assets.json'; a=json.load(open(p)); specs=[('desk.bundle.css','desk.bundle.','/home/frappe/frappe-bench/sites/assets/frappe/dist/css','/assets/frappe/dist/css/'),('email.bundle.css','email.bundle.','/home/frappe/frappe-bench/sites/assets/frappe/dist/css','/assets/frappe/dist/css/'),('login.bundle.css','login.bundle.','/home/frappe/frappe-bench/sites/assets/frappe/dist/css','/assets/frappe/dist/css/'),('print.bundle.css','print.bundle.','/home/frappe/frappe-bench/sites/assets/frappe/dist/css','/assets/frappe/dist/css/'),('print_format.bundle.css','print_format.bundle.','/home/frappe/frappe-bench/sites/assets/frappe/dist/css','/assets/frappe/dist/css/'),('report.bundle.css','report.bundle.','/home/frappe/frappe-bench/sites/assets/frappe/dist/css','/assets/frappe/dist/css/'),('web_form.bundle.css','web_form.bundle.','/home/frappe/frappe-bench/sites/assets/frappe/dist/css','/assets/frappe/dist/css/'),('website.bundle.css','website.bundle.','/home/frappe/frappe-bench/sites/assets/frappe/dist/css','/assets/frappe/dist/css/'),('erpnext-web.bundle.css','erpnext-web.bundle.','/home/frappe/frappe-bench/sites/assets/erpnext/dist/css','/assets/erpnext/dist/css/'),('erpnext.bundle.css','erpnext.bundle.','/home/frappe/frappe-bench/sites/assets/erpnext/dist/css','/assets/erpnext/dist/css/'),('erpnext_email.bundle.css','erpnext_email.bundle.','/home/frappe/frappe-bench/sites/assets/erpnext/dist/css','/assets/erpnext/dist/css/')]; [a.__setitem__(k,pub+os.path.basename(sorted(m)[-1])) for k,pfx,root,pub in specs for m in [glob.glob(root+'/'+pfx+'*.css')] if m]; json.dump(a,open(p,'w'),indent=4); print('assets.json synced to existing CSS files')"

sync-assets-dev-frontend:
	rm -rf /tmp/frappe-dist-sync && mkdir -p /tmp/frappe-dist-sync
	docker cp frappe_docker-backend-1:/home/frappe/frappe-bench/sites/assets/frappe/dist/. /tmp/frappe-dist-sync/frappe-dist
	docker cp frappe_docker-backend-1:/home/frappe/frappe-bench/sites/assets/erpnext/dist/. /tmp/frappe-dist-sync/erpnext-dist
	docker cp frappe_docker-backend-1:/home/frappe/frappe-bench/sites/assets/assets.json /tmp/frappe-dist-sync/assets.json
	$(COMPOSE_DEV) exec -T -u root frontend bash -lc "rm -rf /home/frappe/frappe-bench/sites/assets/frappe/dist/* /home/frappe/frappe-bench/sites/assets/erpnext/dist/*"
	docker cp /tmp/frappe-dist-sync/frappe-dist/. frappe_docker-frontend-1:/home/frappe/frappe-bench/sites/assets/frappe/dist
	docker cp /tmp/frappe-dist-sync/erpnext-dist/. frappe_docker-frontend-1:/home/frappe/frappe-bench/sites/assets/erpnext/dist
	docker cp /tmp/frappe-dist-sync/assets.json frappe_docker-frontend-1:/home/frappe/frappe-bench/sites/assets/assets.json
	$(COMPOSE_DEV) exec -T -u root frontend bash -lc "chown -R frappe:frappe /home/frappe/frappe-bench/sites/assets/frappe/dist /home/frappe/frappe-bench/sites/assets/erpnext/dist /home/frappe/frappe-bench/sites/assets/assets.json"
	docker restart frappe_docker-frontend-1

build-assets-dev: build-assets-dev-backend sync-assets-dev-frontend

refresh-ui-dev: migrate-dev build-assets-dev clear-dev

export-doctype-dev:
	@if [ -z "$(DOCNAME)" ]; then \
		echo "Ошибка: укажите DOCNAME. Пример:"; \
		echo "  make export-doctype-dev DOCNAME='myProba'"; \
		exit 1; \
	fi
	$(COMPOSE_DEV) exec backend bench --site $(SITE_DEV) export-doc "DocType" "$(DOCNAME)"

export-all-dev:
	$(COMPOSE_DEV) exec backend bench --site $(SITE_DEV) export-fixtures

export-ui-dev:
	@set -e; \
	echo "==> Экспорт fixtures"; \
	$(COMPOSE_DEV) exec backend bench --site $(SITE_DEV) export-fixtures; \
	echo "==> Экспорт стандартных DocType модуля Designers"; \
	$(COMPOSE_DEV) exec -T backend bench --site $(SITE_DEV) execute frappe.get_all --kwargs "{'doctype':'DocType','filters':{'module':'Designers','custom':0},'pluck':'name'}" \
	| python3 -c "import ast,sys; print('\n'.join(ast.literal_eval(sys.stdin.read().strip() or '[]')))" \
	| while IFS= read -r name; do \
		[ -n "$$name" ] && $(COMPOSE_DEV) exec -T backend bench --site $(SITE_DEV) export-doc "DocType" "$$name"; \
	done || true; \
	echo "==> Экспорт стандартных Web Form модуля Designers"; \
	$(COMPOSE_DEV) exec -T backend bench --site $(SITE_DEV) execute frappe.get_all --kwargs "{'doctype':'Web Form','filters':{'module':'Designers','is_standard':1},'pluck':'name'}" \
	| python3 -c "import ast,sys; print('\n'.join(ast.literal_eval(sys.stdin.read().strip() or '[]')))" \
	| while IFS= read -r name; do \
		[ -n "$$name" ] && $(COMPOSE_DEV) exec -T backend bench --site $(SITE_DEV) export-doc "Web Form" "$$name"; \
	done || true; \
	echo "==> Экспорт Workspace модуля Designers"; \
	$(COMPOSE_DEV) exec -T backend bench --site $(SITE_DEV) execute frappe.get_all --kwargs "{'doctype':'Workspace','filters':{'module':'Designers'},'pluck':'name'}" \
	| python3 -c "import ast,sys; print('\n'.join(ast.literal_eval(sys.stdin.read().strip() or '[]')))" \
	| while IFS= read -r name; do \
		[ -n "$$name" ] && $(COMPOSE_DEV) exec -T backend bench --site $(SITE_DEV) export-doc "Workspace" "$$name"; \
	done || true; \
	echo "==> Готово"

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
	  --tag $(CUSTOM_IMAGE):$(CUSTOM_TAG) \
	  -f images/custom/Containerfile .

up-with-built-image:
	CUSTOM_IMAGE=$(CUSTOM_IMAGE) CUSTOM_TAG=$(CUSTOM_TAG) $(COMPOSE_BASE) up -d --force-recreate

push-image:
	docker push $(CUSTOM_IMAGE):$(CUSTOM_TAG)

release: build-image-from-bench push-image

prod-up:
	$(COMPOSE_BASE) up -d

prod-down:
	$(COMPOSE_BASE) down

prod-logs:
	$(COMPOSE_BASE) logs -f --tail=200

migrate-prod:
	$(COMPOSE_BASE) exec backend bench --site $(SITE_PROD) migrate

clear-prod:
	$(COMPOSE_BASE) exec backend bench --site $(SITE_PROD) clear-cache

list-apps-prod:
	$(COMPOSE_BASE) exec backend bench --site $(SITE_PROD) list-apps

deploy-remote:
	ssh $(REMOTE_HOST) "cd $(REMOTE_DIR) && \
	  CUSTOM_IMAGE=$(CUSTOM_IMAGE) CUSTOM_TAG=$(CUSTOM_TAG) \
	  docker compose -f compose.yaml -f overrides/compose.mariadb.yaml -f overrides/compose.redis.yaml pull && \
	  CUSTOM_IMAGE=$(CUSTOM_IMAGE) CUSTOM_TAG=$(CUSTOM_TAG) \
	  docker compose -f compose.yaml -f overrides/compose.mariadb.yaml -f overrides/compose.redis.yaml up -d && \
	  docker compose -f compose.yaml -f overrides/compose.mariadb.yaml -f overrides/compose.redis.yaml exec backend bench --site $(SITE_PROD) migrate && \
	  docker compose -f compose.yaml -f overrides/compose.mariadb.yaml -f overrides/compose.redis.yaml exec backend bench --site $(SITE_PROD) clear-cache"
