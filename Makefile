.PHONY: build app run install clean

build:
	swift build

app:
	Scripts/build-app.sh release

run: app
	open build/MenuTerm.app

install: app
	rm -rf /Applications/MenuTerm.app
	cp -R build/MenuTerm.app /Applications/MenuTerm.app
	@echo "installed to /Applications/MenuTerm.app"

clean:
	rm -rf build .build
