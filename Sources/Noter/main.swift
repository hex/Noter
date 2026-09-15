// ABOUTME: Entry point. Invoked as `noter` (a symlink to the app binary) it runs the command line and exits;
// ABOUTME: invoked as the app it bootstraps NSApplication with AppDelegate for the panel lifecycle.

import AppKit
import NoterKit

let invokedAs = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
if invokedAs == "noter" {
    let storage = Storage(rootDirectory: Storage.resolveRootDirectory())
    do { try Storage.migrate(from: Storage.legacyRootDirectory(), to: storage.rootDirectory) } catch {
        FileHandle.standardError.write(Data("noter: library migration failed: \(error)\n".utf8))
    }
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["mcp"] {
        MCPServer(storage: storage).serve()
        exit(0)
    }
    let stdin = arguments.contains("-") ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : ""
    let result = CLI.run(arguments: arguments, storage: storage, stdin: stdin)
    FileHandle.standardOutput.write(Data(result.stdout.utf8))
    FileHandle.standardError.write(Data(result.stderr.utf8))
    exit(result.exitCode)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
