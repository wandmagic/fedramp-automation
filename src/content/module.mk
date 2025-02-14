# Variables
OSCAL_VERSION := $(shell node src/scripts/ci-get-version.js package oscal)
OSCAL_CLI_VERSION := $(shell node src/scripts/ci-get-version.js tool oscal-cli) 
OSCAL_SERVER_VERSION := $(shell node src/scripts/ci-get-version.js tool oscal-server)
OSCAL_SERVER_PATH := $(shell node -e "console.log(process.cwd())")

SRC_DIR = ./src
DIST_DIR = ./dist
XML_DIR = $(DIST_DIR)/content/rev5/baselines/xml
JSON_DIR = $(DIST_DIR)/content/rev5/baselines/json
YAML_DIR = $(DIST_DIR)/content/rev5/baselines/yaml
XMLLINT := $(shell command -v xmllint 2>/dev/null || command -v /usr/bin/xmllint 2>/dev/null || command -v /mingw64/bin/xmllint 2>/dev/null)

# Format configuration
XML_FILES := $(shell find $(XML_DIR) -type f -name "*.xml" 2>/dev/null)
JSON_FILES := $(shell find $(JSON_DIR) -type f -name "*.json" 2>/dev/null)
YAML_FILES := $(shell find $(YAML_DIR) -type f -name "*.yaml" -o -name "*.yml" 2>/dev/null)

.PHONY: init-content
init-content:
	@npm install
	$(OSCAL_CLI) use $(OSCAL_CLI_VERSION)
	$(OSCAL_CLI) server update -t $(OSCAL_SERVER_VERSION)
	$(OSCAL_CLI) server start -bg
	@(command -v xmllint >/dev/null 2>&1 || (command -v apt-get >/dev/null 2>&1 && sudo apt-get install -y libxml2-utils) || (command -v brew >/dev/null 2>&1 && brew install libxml2) || (command -v choco >/dev/null 2>&1 && choco install xsltproc) || echo "Please install xmllint manually")


# Generate content and perform conversions
.PHONY: build-content
build-content:
	@echo "Producing artifacts for baselines..."
	$(OSCAL_CLI) convert -f $(SRC_DIR)/content/rev5/baselines/xml -o $(DIST_DIR)/content/rev5/baselines/ -s
	@echo "Producing artifacts for SSP..."
	$(OSCAL_CLI) convert -f $(SRC_DIR)/content/rev5/templates/ssp/xml -o $(DIST_DIR)/content/rev5/templates/ssp -s
	@echo "Producing artifacts for POAM..."
	$(OSCAL_CLI) convert -f $(SRC_DIR)/content/rev5/templates/poam/xml -o $(DIST_DIR)/content/rev5/templates/poam -s
	@echo "Producing artifacts for SAP..."
	$(OSCAL_CLI) convert -f $(SRC_DIR)/content/rev5/templates/sap/xml -o $(DIST_DIR)/content/rev5/templates/sap -s
	@echo "Producing artifacts for SAR..."
	$(OSCAL_CLI) convert -f $(SRC_DIR)/content/rev5/templates/sar/xml -o $(DIST_DIR)/content/rev5/templates/sar -s

	@echo "Resolving FedRAMP HIGH baseline profile..."
	$(OSCAL_CLI) resolve -f $(SRC_DIR)/content/rev5/baselines/xml/FedRAMP_rev5_HIGH-baseline_profile.xml -o $(XML_DIR)/FedRAMP_rev5_HIGH-baseline-resolved-profile_catalog.xml -s
	@echo "Resolving FedRAMP MODERATE baseline profile..."
	$(OSCAL_CLI) resolve -f $(SRC_DIR)/content/rev5/baselines/xml/FedRAMP_rev5_MODERATE-baseline_profile.xml -o $(XML_DIR)/FedRAMP_rev5_MODERATE-baseline-resolved-profile_catalog.xml -s
	@echo "Resolving FedRAMP LOW baseline profile..."
	$(OSCAL_CLI) resolve -f $(SRC_DIR)/content/rev5/baselines/xml/FedRAMP_rev5_LOW-baseline_profile.xml -o $(XML_DIR)/FedRAMP_rev5_LOW-baseline-resolved-profile_catalog.xml -s
	@echo "Resolving FedRAMP LI-SaaS baseline profile..."
	$(OSCAL_CLI) resolve -f $(SRC_DIR)/content/rev5/baselines/xml/FedRAMP_rev5_LI-SaaS-baseline_profile.xml -o $(XML_DIR)/FedRAMP_rev5_LI-SaaS-baseline-resolved-profile_catalog.xml -s

	@echo "Converting Profiles to JSON..."
	$(OSCAL_CLI) convert -f $(XML_DIR) -o $(JSON_DIR) -t JSON -s
	@echo "Converting Profiles to YAML..."
	$(OSCAL_CLI) convert -f $(XML_DIR) -o $(YAML_DIR) -t YAML -s

# Format files
.PHONY: format-xml
format-xml:
	@echo "Formatting XML files..."
	@for file in $(XML_FILES); do \
		echo "Formatting $$file..."; \
		$(XMLLINT) --format --output "$$file" "$$file"; \
	done

.PHONY: format-json
format-json:
	@echo "Formatting JSON files..."
	@for file in $(JSON_FILES); do \
		if ! echo "$$file" | grep -q "min"; then \
			echo "Formatting $$file..."; \
			npx prettier --write --parser json "$$file"; \
		fi \
	done
.PHONY: format-yaml
format-yaml:
	@echo "Formatting YAML files..."
	@for file in $(YAML_FILES); do \
		echo "Formatting $$file..."; \
		npx prettier --write --parser yaml "$$file"; \
	done

# Combined format target
.PHONY: format-content
format-content: format-xml format-json format-yaml
	@echo "All formatting complete!"

.PHONY: test-content
test-content: 
	@echo "Validating Source files"
	@$(OSCAL_CLI) validate -f  $(SRC_DIR)/content/rev5/baselines/xml/FedRAMP_rev5_HIGH-baseline_profile.xml -s
	@$(OSCAL_CLI) validate -f  $(SRC_DIR)/content/rev5/baselines/xml/FedRAMP_rev5_LI-SaaS-baseline_profile.xml -s
	@$(OSCAL_CLI) validate -f  $(SRC_DIR)/content/rev5/baselines/xml/FedRAMP_rev5_LOW-baseline_profile.xml -s
	@$(OSCAL_CLI) validate -f  $(SRC_DIR)/content/rev5/baselines/xml/FedRAMP_rev5_MODERATE-baseline_profile.xml	-s


.PHONY: test-dist-content
test-dist-content: 
	@echo "Validating Output files"
	@set -e; \
	validation_failed=0; \
	for file in $(YAML_FILES); do \
		echo "Validating $$file..."; \
		if ! $(OSCAL_CLI) validate -s -f "$$file"; then \
			echo "Error: Validation failed for YAML file: $$file"; \
			validation_failed=1; \
		fi; \
	done; \
	for file in $(JSON_FILES); do \
		echo "Validating $$file..."; \
		if ! $(OSCAL_CLI) validate -s -f "$$file"; then \
			echo "Error: Validation failed for JSON file: $$file"; \
			validation_failed=1; \
		fi; \
	done; \
	for file in $(XML_FILES); do \
		echo "Validating $$file..."; \
		if ! $(OSCAL_CLI) validate -s -f "$$file"; then \
			echo "Error: Validation failed for XML file: $$file"; \
			validation_failed=1; \
		fi; \
	done; \
	if [ $$validation_failed -eq 1 ]; then \
		echo "One or more validations failed"; \
		exit 1; \
	fi

.PHONY: test-legacy-content
test-legacy-content: format
	@echo "Validating Source files"
	@$(OSCAL_CLI) validate -f  $(SRC_DIR)/content/rev4/baselines/ -r -s