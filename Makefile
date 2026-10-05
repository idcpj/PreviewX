SWIFT ?= swift
XCODEBUILD ?= xcodebuild
DERIVED_DATA ?= .build/xcode

.PHONY: build test xcode-build archive lint preview providers install

build:
	$(SWIFT) build

test:
	$(SWIFT) test

xcode-build:
	$(XCODEBUILD) -project PreviewX.xcodeproj -scheme PreviewX -configuration Debug -derivedDataPath $(DERIVED_DATA) DEVELOPMENT_TEAM=T3L8L27V37 build

archive:
	$(XCODEBUILD) -project PreviewX.xcodeproj -scheme PreviewX -configuration Release -derivedDataPath $(DERIVED_DATA) -archivePath $(DERIVED_DATA)/PreviewX.xcarchive archive

install: xcode-build
	pkill -9 -f PreviewXQuickLook || true
	killall QuickLookUIService || true
	rm -rf /Applications/PreviewX.app
	cp -R $(DERIVED_DATA)/Build/Products/Debug/PreviewX.app /Applications/PreviewX.app
	/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Applications/PreviewX.app
	pluginkit -a /Applications/PreviewX.app/Contents/PlugIns/PreviewXQuickLook.appex
	qlmanage -r && qlmanage -r cache

lint:
	plutil -lint App/Info.plist QuickLookExtension/Info.plist PreviewX.xcodeproj/project.pbxproj
	$(SWIFT) build

preview:
	$(SWIFT) run previewx preview $(FILE)

providers:
	$(SWIFT) run previewx providers doctor
