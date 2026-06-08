import Foundation

/// Logs to both stdout and `/tmp/fenetre.log`.
///
/// The file is what makes debugging reliable: fenêtre must be launched via
/// LaunchServices (`open`) for its Accessibility grant to apply, but that
/// detaches stdout from the terminal. The log file is readable either way
/// (`tail -F /tmp/fenetre.log`). Truncated fresh on each launch.
enum Log {
    private static let path = "/tmp/fenetre.log"

    private static let handle: FileHandle? = {
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func info(_ message: String) {
        print(message)
        if let data = (message + "\n").data(using: .utf8) {
            handle?.write(data)
        }
    }
}
