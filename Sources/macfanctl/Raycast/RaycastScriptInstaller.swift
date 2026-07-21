import Foundation

struct RaycastScriptInstaller {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static func destinationDirectory(
        directoryPath: String? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let directoryPath {
            return URL(
                fileURLWithPath: NSString(string: directoryPath).expandingTildeInPath,
                isDirectory: true
            )
        }
        return homeDirectory.appendingPathComponent("raycast-script", isDirectory: true)
    }

    func install(_ scripts: [RaycastScript], at destination: URL) throws -> [URL] {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        return try scripts.map { script in
            let file = destination.appendingPathComponent(script.filename)
            try Data(script.contents.utf8).write(to: file, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: file.path
            )
            return file
        }
    }
}
