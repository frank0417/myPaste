# Paste packaging helpers
#
# On macOS:
#   make package          -> dist/Paste.app + dist/Paste-1.0.0.dmg
#   make package-signed   -> signed DMG (requires Developer ID)
#   make package-pkg      -> also emit .pkg
#   make app-store        -> App Store export

.PHONY: package package-signed package-pkg package-notarize app-store clean help

VERSION ?= 1.0.0

help:
	@echo "Targets:"
	@echo "  make package            Build Release .app + .dmg (ad-hoc)"
	@echo "  make package-signed     Sign with Developer ID + .dmg"
	@echo "  make package-pkg        Signed .dmg + .pkg"
	@echo "  make package-notarize   Sign, notarize, staple"
	@echo "  make app-store          Archive/export for App Store Connect"
	@echo "  make clean              Remove build/ and dist/"

package:
	chmod +x scripts/package.sh
	./scripts/package.sh --version $(VERSION)

package-signed:
	chmod +x scripts/package.sh
	./scripts/package.sh --sign --version $(VERSION)

package-pkg:
	chmod +x scripts/package.sh
	./scripts/package.sh --sign --pkg --version $(VERSION)

package-notarize:
	chmod +x scripts/package.sh
	./scripts/package.sh --sign --pkg --notarize --version $(VERSION)

app-store:
	chmod +x scripts/package.sh
	./scripts/package.sh --app-store --version $(VERSION)

clean:
	rm -rf build dist
	mkdir -p dist
