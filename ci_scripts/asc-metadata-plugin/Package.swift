// swift-tools-version: 6.0
import PackageDescription

// App Store Connect へメタ情報を同期する asc-metadata-cli を
// CI（Xcode Cloud の Release ワークフロー）から実行するための専用パッケージ。
//
// asc-metadata-cli はプレビルドの artifactbundle として配布されているため、
// binaryTarget として取り込み、command plugin 経由で実行する。
// これにより SDK をフルコンパイルせずに済み、CI の実行時間を短縮できる。
//
// バージョン更新時は url / checksum を新しいリリースのものに差し替える。
// checksum は `swift package compute-checksum asc-metadata-cli.artifactbundle.zip`
// で算出できる（リリースの .checksum アセットの値と一致する）。
let package = Package(
    name: "asc-metadata-plugin",
    targets: [
        .binaryTarget(
            name: "asc-metadata-cli",
            url: "https://github.com/stotic-dev/asc-metadata-cli/releases/download/v0.1.0/asc-metadata-cli.artifactbundle.zip",
            checksum: "ca110542bff1f9810ee9e3d5a476264232c98723d4ec71656bfcdf0434bfde1f"
        ),
        .plugin(
            name: "ASCMetadataSync",
            capability: .command(
                intent: .custom(
                    verb: "asc-metadata-sync",
                    description: "App Store Connect に新バージョン・リリースノート・スクリーンショットを同期する"
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .all(),
                        reason: "App Store Connect API と通信してメタ情報を同期するため"
                    )
                ]
            ),
            dependencies: ["asc-metadata-cli"]
        ),
    ]
)
