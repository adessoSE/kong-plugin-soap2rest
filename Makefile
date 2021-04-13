DEV_ROCKS = busted "lua-cjson 2.1.0.6-1" "xml2lua 1.4-3" "lyaml 6.2.7-1" "multipart 0.5.9-1" "base64 1.5-3" "luacov 0.12.0" "busted" "luacheck" "luacov" "luacov-console" "lua-llthreads2"
PLUGIN_NAME := kong-plugin-soap2rest

.PHONY: install uninstall dev lint test test-integration test-plugins test-all clean

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(dir $(mkfile_path))
DEV_PACKAGE_PATH := $(current_dir)lua_modules/share/lua/5.1/?
KONG_path ?= /kong
BUSTED_path ?= bin/busted
BUSTED_args := --config-file=$(current_dir)/.busted

define set_env
	@cp $(current_dir)/.luacov $(KONG_path)/.luacov
	@rm -f luacov.stats.out luacov.report.out luacov.report.out.index \
	@eval $$(luarocks path); \
	LUA_PATH="$(DEV_PACKAGE_PATH).lua;$$LUA_PATH" LUA_CPATH="$(DEV_PACKAGE_PATH).so;$$LUA_CPATH"; \
	export KONG_SPEC_TEST_CONF_PATH="$(current_dir)/spec/kong_tests.conf"; \
	cd $(KONG_path);
endef

define coverage
	@mv $(KONG_path)/luacov.stats.out $(current_dir)/luacov.stats.out
	@luacov-console /kong-plugin/lua_modules/share/lua/5.1/kong/plugins/soap2rest; \
	luacov-console -s
endef

setup:
	@for rock in $(DEV_ROCKS) ; do \
		if luarocks list --porcelain $$rock | grep -q "installed" ; then \
			echo $$rock already installed, skipping ; \
		else \
			echo $$rock not found, installing via luarocks... ; \
			luarocks install $$rock; \
		fi \
	done;

check:
	@for rock in $(DEV_ROCKS) ; do \
		if luarocks list --porcelain $$rock | grep -q "installed" ; then \
			echo $$rock is installed ; \
		else \
			echo $$rock is not installed ; \
		fi \
	done;

lint:
	@cd kong/plugins/soap2rest && luacheck -q .

install:
	sudo luarocks make $(PLUGIN_NAME)-*.rockspec

uninstall:
	sudo luarocks remove $(PLUGIN_NAME)-*.rockspec

install-dev:
	@luarocks make --tree lua_modules $(PLUGIN_NAME)-*.rockspec

test: install-dev
	$(call set_env) \
	$(BUSTED_path) $(BUSTED_args) $(current_dir)spec/soap2rest

test-unit: install-dev
	$(call set_env) \
	$(BUSTED_path) $(BUSTED_args) $(current_dir)spec/soap2rest/01-unit

test-integration: install-dev
	$(call set_env) \
	$(BUSTED_path) $(BUSTED_args) $(current_dir)spec/soap2rest/02-integration

coverage : test
	$(call coverage)

coverage-unit : test-unit
	$(call coverage)

coverage-integration : test-integration
	$(call coverage)

clean:
	@echo "removing $(PLUGIN_NAME)"
	-@luarocks remove --tree lua_modules $(PLUGIN_NAME)-*.rockspec >/dev/null 2>&1 ||: