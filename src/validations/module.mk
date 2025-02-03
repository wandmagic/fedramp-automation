
# Get tool versions using Node script
OSCAL_VERSION := $(shell node src/scripts/ci-get-version.js package oscal)
OSCAL_CLI_VERSION := $(shell node src/scripts/ci-get-version.js tool oscal-cli) 
OSCAL_SERVER_VERSION := $(shell node src/scripts/ci-get-version.js tool oscal-server)
OSCAL_SERVER_PATH := $(shell node -e "console.log(process.cwd())")

# Optional: Add version checking targets
check-versions:
	@echo "Using versions:"
	@echo "OSCAL CLI: $(OSCAL_CLI_VERSION)"
	@echo "OSCAL Server: $(OSCAL_SERVER_VERSION)"
	@echo "OSCAL JS: $(OSCAL_VERSION)"
	@echo "OSCAL SERVER ALLOWED DIR: $(OSCAL_SERVER_PATH)"
OSCAL_CLI = npx oscal@$(OSCAL_VERSION)
SRC_DIR = ./src
DIST_DIR = ./dist
REV5_BASELINES = ./dist/content/rev5/baselines
REV5_TEMPLATES = ./dist/content/rev5/templates

# Preparation
.PHONY: init-validations
init-validations:
	@echo "Installing node modules..."
	npm install
	$(OSCAL_CLI) use $(OSCAL_CLI_VERSION)
	$(OSCAL_CLI) server update -t $(OSCAL_SERVER_VERSION)

# Style lint
.PHONY: lint-style
lint-validations:
	@echo "Validating against style guide"
	npm run test:style

# Validation
.PHONY: build-validations
build-validations:
	@echo "Running Cucumber Tests"
	$(OSCAL_CLI) server stop
	npx cross-env OSCAL_SERVER_PATH=$(OSCAL_SERVER_PATH)  $(OSCAL_CLI) server start -bg
	@npm run test:server
	$(OSCAL_CLI) server stop

clean-validations:
	@echo "Nothing to clean"

update:
	npm install
	$(OSCAL_CLI) use latest
constraint:
	npm run constraint
metaquery:
	npm run mq

test-validations:
	@echo "Validating rev5 artifacts recursively..."
	$(OSCAL_CLI) validate -f $(REV5_BASELINES) -e ./src/validations/constraints/fedramp-external-constraints.xml -r
	$(OSCAL_CLI) validate -f $(REV5_TEMPLATES) -e ./src/validations/constraints/fedramp-external-constraints.xml -r
