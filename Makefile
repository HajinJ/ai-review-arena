.PHONY: test lint benchmark e2e install all

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
