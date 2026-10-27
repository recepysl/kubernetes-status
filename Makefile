.PHONY: build app dmg run install uninstall once selftest test screenshots icon clean

build:
	swift build -c release

app:
	./scripts/build.sh

dmg:
	./scripts/make-dmg.sh

run: app
	open KubernetesStatus.app

install: app
	rm -rf /Applications/KubernetesStatus.app
	cp -R KubernetesStatus.app /Applications/
	open /Applications/KubernetesStatus.app

uninstall:
	./scripts/uninstall.sh

once:
	swift run KubernetesStatus --once

selftest:
	swift run KubernetesStatus --selftest

test:
	./scripts/test.sh

screenshots:
	swift run KubernetesStatus --render-screenshots docs/images

icon:
	./tools/make-icns.sh

clean:
	rm -rf .build KubernetesStatus.app dist
