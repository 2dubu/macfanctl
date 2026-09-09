import Darwin
import Foundation

/// Checks for controllers known to overwrite another client's manual fan settings.
/// This is a preflight snapshot, not an exclusive lock on the SMC: an app can
/// still start after the check. The caller must run it before opening the SMC.
enum FanControlConflict {
    struct RunningApplication: Equatable {
        let processID: pid_t
        let bundleIdentifier: String
    }

    enum CheckError: Error, LocalizedError, CustomStringConvertible, Equatable {
        case controllerRunning(processID: pid_t)
        case inventoryUnavailable(String)

        var description: String {
            switch self {
            case .controllerRunning(let processID):
                return "Macs Fan Control is running (PID \(processID)) and can reset manual fan settings. "
                    + "Quit Macs Fan Control from its menu, then run this command again. "
                    + "`macfanctl auto` remains available."
            case .inventoryUnavailable(let reason):
                return "Could not check for conflicting fan controllers: \(reason). "
                    + "No fan settings were changed. `macfanctl auto` remains available."
            }
        }

        var errorDescription: String? { description }
    }

    // Verified from Macs Fan Control's CFBundleIdentifier. Its separately
    // installed smcwrite helper is not a GUI controller and must not match.
    static let macsFanControlBundleIdentifier = "com.crystalidea.macsfancontrol"

    static func check(
        inventory: () throws -> [RunningApplication] = runningApplications
    ) throws {
        let applications: [RunningApplication]
        do {
            applications = try inventory()
        } catch let error as CheckError {
            throw error
        } catch {
            throw CheckError.inventoryUnavailable(String(describing: error))
        }

        if let conflict = applications.first(where: {
            $0.bundleIdentifier == macsFanControlBundleIdentifier
        }) {
            throw CheckError.controllerRunning(processID: conflict.processID)
        }
    }

    /// libproc enumerates native processes without depending on the invoking
    /// user's GUI session, so this also works when the CLI is invoked with sudo.
    /// Fail closed if enumeration or a live process's path cannot be inspected.
    /// ENOENT/ESRCH are expected when a process exits during the snapshot.
    static func runningApplications() throws -> [RunningApplication] {
        errno = 0
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else {
            throw inventoryError("enumerating processes")
        }

        var capacity = Int(estimate) + 64
        for _ in 0..<3 {
            var processIDs = [pid_t](repeating: 0, count: capacity)
            errno = 0
            let count = processIDs.withUnsafeMutableBytes {
                proc_listallpids($0.baseAddress, Int32($0.count))
            }
            guard count > 0 else {
                throw inventoryError("enumerating processes")
            }
            // A full buffer may omit newly launched processes. Retry with room
            // for a complete snapshot instead of accepting a truncated list.
            guard Int(count) < capacity else {
                capacity *= 2
                continue
            }

            var applications: [RunningApplication] = []
            for processID in processIDs.prefix(Int(count)) where processID > 0 {
                // PROC_PIDPATHINFO_MAXSIZE is defined as 4 * MAXPATHLEN in
                // sys/proc_info.h; that expression is not imported into Swift.
                var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
                errno = 0
                let length = path.withUnsafeMutableBytes {
                    proc_pidpath(processID, $0.baseAddress, UInt32($0.count))
                }
                if length <= 0 {
                    let error = errno
                    if error == ESRCH || error == ENOENT { continue }
                    throw inventoryError("reading executable path for PID \(processID)", code: error)
                }
                let executable = URL(fileURLWithPath: String(decoding: path.prefix { $0 != 0 }, as: UTF8.self))
                if let application = application(processID: processID, executableURL: executable) {
                    applications.append(application)
                }
            }
            return applications
        }

        throw CheckError.inventoryUnavailable("the process list kept changing during inspection")
    }

    /// Match the bundle's main executable, not its display name, enclosing app,
    /// or helper executables. Renaming or moving the .app does not bypass this.
    static func application(processID: pid_t, executableURL: URL) -> RunningApplication? {
        let macOSDirectory = executableURL.deletingLastPathComponent()
        let contentsDirectory = macOSDirectory.deletingLastPathComponent()
        let bundleURL = contentsDirectory.deletingLastPathComponent()
        guard macOSDirectory.lastPathComponent == "MacOS",
              contentsDirectory.lastPathComponent == "Contents",
              bundleURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: bundleURL),
              let identifier = bundle.bundleIdentifier,
              let mainExecutable = bundle.executableURL,
              mainExecutable.resolvingSymlinksInPath() == executableURL.resolvingSymlinksInPath()
        else { return nil }

        return RunningApplication(processID: processID, bundleIdentifier: identifier)
    }

    private static func inventoryError(_ operation: String, code: Int32 = errno) -> CheckError {
        CheckError.inventoryUnavailable("\(operation): \(String(cString: strerror(code)))")
    }
}
