import Foundation
import PackagePlugin

// asc-metadata-cli（binaryTarget）を実行する command plugin。
// このプラグインへ渡された引数はそのまま asc-metadata-cli に転送する。
//
// 例:
//   swift package --package-path ci_scripts/asc-metadata-plugin \
//       --disable-sandbox --allow-network-connections all \
//       asc-metadata-sync \
//       sync --bundle-id <id> --version <x.y.z> --metadata-dir <path>
@main
struct ASCMetadataSync: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "asc-metadata-cli")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.path.string)
        process.arguments = arguments
        // ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY などの環境変数を引き継ぐ
        process.environment = ProcessInfo.processInfo.environment

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            Diagnostics.error("asc-metadata-cli failed with exit code \(process.terminationStatus)")
            throw PluginError.toolFailed(code: process.terminationStatus)
        }
    }
}

enum PluginError: Error, CustomStringConvertible {
    case toolFailed(code: Int32)

    var description: String {
        switch self {
        case .toolFailed(let code):
            return "asc-metadata-cli exited with non-zero status \(code)"
        }
    }
}
