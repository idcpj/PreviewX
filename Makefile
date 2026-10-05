SWIFT ?= swift
XCODEBUILD ?= xcodebuild
DERIVED_DATA ?= .build/xcode

DEVELOPMENT_TEAM ?= WAVU44HS32

.PHONY: build test xcode-build archive lint preview providers install

build:
	$(SWIFT) build

test:
	$(SWIFT) test

xcode-build:
	@if [ -n "$$DEVELOPMENT_TEAM" ]; then \
		$(XCODEBUILD) -project PreviewX.xcodeproj -scheme PreviewX -configuration Debug -derivedDataPath $(DERIVED_DATA) DEVELOPMENT_TEAM="$$DEVELOPMENT_TEAM" build; \
	elif ! $(XCODEBUILD) -project PreviewX.xcodeproj -scheme PreviewX -configuration Debug -derivedDataPath $(DERIVED_DATA) build; then \
		echo "⚠️ 默认签名构建失败，正在尝试使用本地 Ad-Hoc 签名构建..."; \
		$(XCODEBUILD) -project PreviewX.xcodeproj -scheme PreviewX -configuration Debug -derivedDataPath $(DERIVED_DATA) CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES build; \
	fi

archive:
	@if [ -n "$$DEVELOPMENT_TEAM" ]; then \
		$(XCODEBUILD) -project PreviewX.xcodeproj -scheme PreviewX -configuration Release -derivedDataPath $(DERIVED_DATA) -archivePath $(DERIVED_DATA)/PreviewX.xcarchive DEVELOPMENT_TEAM="$$DEVELOPMENT_TEAM" archive; \
	else \
		$(XCODEBUILD) -project PreviewX.xcodeproj -scheme PreviewX -configuration Release -derivedDataPath $(DERIVED_DATA) -archivePath $(DERIVED_DATA)/PreviewX.xcarchive archive; \
	fi

install: xcode-build
	killall PreviewX || true
	pkill -9 -f PreviewXQuickLook || true
	killall QuickLookUIService || true
	rm -rf /Applications/PreviewX.app
	cp -R $(DERIVED_DATA)/Build/Products/Debug/PreviewX.app /Applications/PreviewX.app
	/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Applications/PreviewX.app
	pluginkit -a /Applications/PreviewX.app/Contents/PlugIns/PreviewXQuickLook.appex
	pluginkit -e use -i com.idcpj.previewx.quicklook || true
	qlmanage -r && qlmanage -r cache
	@echo "✅ PreviewX 已成功安装到 /Applications 并注册 Quick Look 扩展！"

lint:
	plutil -lint App/Info.plist QuickLookExtension/Info.plist PreviewX.xcodeproj/project.pbxproj
	$(SWIFT) build

preview:
	$(SWIFT) run previewx preview $(FILE)

providers:
	$(SWIFT) run previewx providers doctor
