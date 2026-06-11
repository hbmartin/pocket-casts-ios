BUNDLE=rbenv exec bundle
LANG_VAR=LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
FASTLANE=$(LANG_VAR) $(BUNDLE) exec fastlane
# Explicit --config prevents SwiftLint from picking up nested configs in
# BuildTools/.build/checkouts/ (e.g., SwiftGenPlugin's .swiftlint.yml).
SWIFTLINT_FROM_BUILDTOOLS=swiftlint lint --working-directory .. --config .swiftlint.yml --quiet
# Parse the human-readable output of simctl
SIMULATOR_NAME = $(shell xcrun simctl list devices available \
	| grep "iPhone" \
	| tail -1 | sed 's/^[[:space:]]*//' | sed 's/ *(.*) *$$//')
SIMULATOR_OS ?= 18.5
XCODE_ANALYZE_SCHEME ?= Pocket Casts Staging
XCODE_ANALYZE_CONFIGURATION ?= StagingDebug
XCODE_ANALYZE_DESTINATION ?= generic/platform=iOS Simulator
XCODE_ANALYZE_DERIVED_DATA_PATH ?= /tmp/pocketcasts-analyze-deriveddata
SEMGREP_SWIFT_ERROR ?= 1
SEMGREP_POCKET_CASTS_ERROR ?= 1

.PHONY: help build clean test lint lint_lenient semgrep_swift_security semgrep_pocket_casts semgrep_tests xcode_static_analyzer static_checks format install_dependencies check_concurrency_warnings

define run_in_buildtools
	@pushd BuildTools && \
	export SDKROOT=$$(xcrun --sdk macosx --show-sdk-path) && \
	swift package plugin \
		--allow-writing-to-directory .. \
		--allow-writing-to-package-directory \
		$(1) && \
	popd
endef

help: ## Show this list of commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

swift_percentage: ## Swift and Obj-C percentage on the project
	./scripts/count.rb

generate_colors: ## Generate colors and themes based on themes.csv
	ruby scripts/themes/generate_themes.rb scripts/themes/theme.csv

generate_code:
	$(call run_in_buildtools,generate-code-for-resources --config ../swiftgen.yml)

lint: ## Lint the codebase
	$(call run_in_buildtools,$(SWIFTLINT_FROM_BUILDTOOLS))

lint_lenient:
	$(call run_in_buildtools,$(SWIFTLINT_FROM_BUILDTOOLS) --lenient)

semgrep_swift_security: ## Run akabe1 Swift/iOS Semgrep security rules
	semgrep scan --config semgrep/swift-security.yml --include "*.swift" --include "**/Package.swift" --include "**/Package.resolved" --include "**/.github/workflows/*.yml" --include "**/scripts/ci/*.sh" --include "**/scripts/build-phases/*.sh" --include "**/semgrep/*.yml" --include "**/semgrep/*.yaml" --include "Makefile" --include "**/Makefile" --include "*.mk" --include "**/*.mk" --exclude "semgrep/tests/**" --metrics off --timeout 0 --disable-version-check $(if $(filter 1,$(SEMGREP_SWIFT_ERROR)),--error,)

semgrep_pocket_casts: ## Run Pocket Casts custom Semgrep rules
	semgrep scan --config semgrep/pocket-casts.yml --include "*.swift" --exclude "semgrep/tests/**" --metrics off --timeout 0 --disable-version-check $(if $(filter 1,$(SEMGREP_POCKET_CASTS_ERROR)),--error,)

semgrep_tests: ## Run Semgrep rule tests
	semgrep test --config semgrep/pocket-casts.yml semgrep/tests/pocket-casts-web-opening.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/swift-security-insecure-storage.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/pocket-casts-keychain.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/swift-security-urlhelper.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/swift-security-concurrency.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/swift-security-pr-feedback.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/swift-security-zendesk-wordpress.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/github-actions-security.yml
	semgrep test --config semgrep/swift-security.yml semgrep/tests/podcasts/Main/MainTabBarController.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/podcasts/ProfileViewController.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/podcasts/RemovedPlusLockedInfo.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/podcasts/RemovedLegacyPayment.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/podcasts/RemovedUserSatisfactionSurvey.swift
	semgrep test --config semgrep/swift-security.yml semgrep/tests/generate-credentials-placeholder-regex.sh

credentials_script_tests: ## Run credentials generation script tests
	ruby scripts/tests/generate_credentials_test.rb

xcode_static_analyzer: ## Run Xcode Static Analyzer for the staging app
	if [ -n "$(XCODE_ANALYZE_DERIVED_DATA_PATH)" ]; then rm -rf "$(XCODE_ANALYZE_DERIVED_DATA_PATH)/SDKStatCaches.noindex"; fi
	xcodebuild -quiet analyze -project podcasts.xcodeproj \
       -scheme "$(XCODE_ANALYZE_SCHEME)" \
       -configuration $(XCODE_ANALYZE_CONFIGURATION) \
       -destination '$(XCODE_ANALYZE_DESTINATION)' \
       -derivedDataPath $(XCODE_ANALYZE_DERIVED_DATA_PATH) \
       CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

static_checks: ## Run SwiftLint, Semgrep, and Xcode Static Analyzer
	$(MAKE) lint
	$(MAKE) credentials_script_tests
	$(MAKE) semgrep_tests
	$(MAKE) semgrep_swift_security
	$(MAKE) semgrep_pocket_casts
	$(MAKE) xcode_static_analyzer

build: ## Builds the Debug configuration using Xcode
	xcodebuild -project podcasts.xcodeproj \
       -scheme pocketcasts \
       -configuration Debug \
       -destination 'generic/platform=iOS Simulator' \
       build

clean: ## Cleans the build artifacts
	xcodebuild -project podcasts.xcodeproj \
       -scheme pocketcasts \
       -configuration Debug \
       clean

ONLY_TESTING ?= PocketCastsTests

test: ## Build and run the PocketCastsTests target with Unit Tests using Xcode
	xcodebuild test -project podcasts.xcodeproj \
	    -scheme pocketcasts \
        -only-testing:$(ONLY_TESTING) \
        -destination 'platform=iOS Simulator,name=$(SIMULATOR_NAME),OS=$(SIMULATOR_OS)'

build_staging: ## Builds using the StagingDebug configuration
	xcodebuild -project podcasts.xcodeproj \
       -scheme "Pocket Casts Staging" \
       -configuration StagingDebug \
       -destination 'generic/platform=iOS Simulator' \
       build

CONCURRENCY_WARNINGS_LOG ?= /tmp/pocketcasts-concurrency-check.log

check_concurrency_warnings: ## Build and fail if strict-concurrency warnings appear under Modules/Sources
	set -o pipefail; \
	xcodebuild -project podcasts.xcodeproj \
	    -scheme "Pocket Casts Staging" \
	    -configuration StagingDebug \
	    -destination 'generic/platform=iOS Simulator' \
	    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
	    build 2>&1 | tee "$(CONCURRENCY_WARNINGS_LOG)" >/dev/null
	@./scripts/ci/check-concurrency-warnings.sh "$(CONCURRENCY_WARNINGS_LOG)"

test_staging: ## Build and run Unit Tests using the StagingDebug configuration
	xcodebuild test -project podcasts.xcodeproj \
	    -scheme "Pocket Casts Staging" \
        -only-testing:$(ONLY_TESTING) \
        -destination 'platform=iOS Simulator,name=$(SIMULATOR_NAME),OS=$(SIMULATOR_OS)'

format: ## Lint and autocorrect linter errors
	$(call run_in_buildtools,$(SWIFTLINT_FROM_BUILDTOOLS) --autocorrect)

install_dependencies: ## Install dependencies to run this project
	bundle install

update_proto: ## Generates the protobuffer Swift files
	./scripts/update_proto.sh $(API_PATH)

external_contributor: ## Generates an empty ApiCredentials.swift so the app builds
	@cp podcasts/Credentials/ApiCredentials.tpl podcasts/Credentials/LocalApiCredentials.swift
	@sed -i '' -e 's/%%{/__ESCAPED_PLACEHOLDER_OPEN__/g' -e 's/%{[^}]*}//g' -e 's/__ESCAPED_PLACEHOLDER_OPEN__/%{/g' "podcasts/Credentials/LocalApiCredentials.swift"
	$(info You're ready to build the app, go ahead! 🎙)
