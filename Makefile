.PHONY: build-rundler
build-rundler:
	cd @rundler && cargo build

.PHONY: terminate
terminate:
	- pkill rundler
	- docker compose down -t 3

.PHONY: setup-v0_7
setup-v0_7:
	$(MAKE) build-rundler
	integration/scripts/setup-v0_7.sh

test-v0_7:

.PHONY: test-spec-integrated-v0_7
test-spec-integrated-v0_7: ## Run v0.7 spec tests in integrated mode
	- cd @rundler/test/spec-tests/v0_7/bundler-spec-tests && pdm install && pdm run update-deps
	\@rundler/test/spec-tests/local/run-spec-tests-v0_7.sh
