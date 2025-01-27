
.PHONY: build-rundler
build-rundler:
	cd @rundler && cargo build

.PHONY: terminate
terminate:
	- pkill rundler
	- docker compose down -t 3

.PHONY: setup
setup:
	$(MAKE) build-rundler
	integration/scripts/setup.sh	

# Integration tests by mocha
.PHONY: integration
integration:
	npm run test

# Unit tests by forge
.PHONY: test
test:
	forge test
