.PHONY: test lint benchmark solo-benchmark e2e install all help

help: ## Show available targets
	@echo "AI Review Arena - Available targets:"
	@echo ""
	@echo "  make test            Run unit + integration + mock E2E tests"
	@echo "  make lint            Run shellcheck on all scripts"
	@echo "  make benchmark       Run benchmark suite (requires codex/gemini CLI)"
	@echo "  make solo-benchmark  Run solo vs arena comparison benchmark"
	@echo "  make e2e             Run full E2E tests (requires codex/gemini CLI)"
	@echo "  make install         Install plugin to ~/.claude/plugins/"
	@echo "  make all             Run lint + test"
	@echo "  make help            Show this help"

test:
	bash tests/run-tests.sh

lint:
	bash tests/run-shellcheck.sh

benchmark:
	bash scripts/run-benchmark.sh

solo-benchmark:
	bash scripts/run-solo-benchmark.sh --verbose

e2e:
	bash tests/run-tests.sh --e2e

install:
	bash install.sh

all: lint test
