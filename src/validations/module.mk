# Variables
OSCAL_CLI = npx oscal@latest
SRC_DIR = ./src
DIST_DIR = ./dist
REV5_BASELINES = ./dist/content/rev5/baselines
REV5_TEMPLATES = ./dist/content/rev5/templates

# Preparation
.PHONY: init-validations
init-validations:
	@echo "Installing node modules..."
	npm install
	$(OSCAL_CLI) use latest

# Validation
.PHONY: build-validations
test-validations:
	@echo "Running Cucumber Tests"
	@npm run test:all

# Validation
.PHONY: build-coverage
build-validations:
	@echo "Testing constraint coverage"
	@npm run test

clean-validations:
	@echo "Nothing to clean"
