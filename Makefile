.PHONY: test runtime dmg

test:
	swift test

runtime:
	./scripts/prepare-runtime.sh

dmg:
	./scripts/build-dmg.sh
