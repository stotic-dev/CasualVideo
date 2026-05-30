.DEFAULT_GOAL := help
.PHONY: help build test verify

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## LocalPackage を iOS シミュレーター向けにビルド
	swift build --package-path LocalPackage --sdk $(shell xcrun --sdk iphonesimulator --show-sdk-path) --triple arm64-apple-ios26.2-simulator

test: ## LocalPackage のテストを実行
	swift test --package-path LocalPackage --enable-code-coverage

verify: build test ## ビルドとテストをまとめて実行（コード検証）
