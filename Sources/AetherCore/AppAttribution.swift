import Darwin
import Foundation

/// Pure-Darwin (`proc_pidpath`) parent-app attribution for per-process bandwidth & outbound sockets.
/// Resolves Electron/Chromium/WebKit helper processes (e.g. `Google Chrome Helper (Renderer)`,
/// `Antigravity Helper`, `Ando Helper`) up to their outermost `.app` bundle in microseconds
/// with zero subprocesses.
public struct ResolvedApp: Sendable, Equatable {
    public let groupKey: String
    public let displayName: String
    public let appBundlePath: String?

    public init(groupKey: String, displayName: String, appBundlePath: String?) {
        self.groupKey = groupKey
        self.displayName = displayName
        self.appBundlePath = appBundlePath
    }

    public var isAppBundle: Bool {
        appBundlePath != nil
    }
}

public enum AppAttribution {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var bundleNames: [String: String] = [:]
    }

    private static let cache = Cache()

    /// Resolves a PID + raw process name into its parent `.app` bundle (if any) and display name.
    public static func resolve(pid: Int, fallbackName: String) -> ResolvedApp {
        let cleanedFallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pid > 0, let execPath = executablePath(forPID: pid) else {
            return ResolvedApp(
                groupKey: "proc:\(cleanedFallback.lowercased())",
                displayName: cleanedFallback,
                appBundlePath: nil
            )
        }

        if let bundlePath = outermostAppBundlePath(forExecutablePath: execPath) {
            let name = bundleDisplayName(at: bundlePath)
            return ResolvedApp(
                groupKey: "app:\(bundlePath.lowercased())",
                displayName: name,
                appBundlePath: bundlePath
            )
        }

        // Non-bundle CLI / system daemon (e.g. `cloudd`, `node`, `git-remote-https`, `CloudTelemetryService`)
        let binaryName = URL(fileURLWithPath: execPath).lastPathComponent
        let display = binaryName.isEmpty ? cleanedFallback : binaryName
        return ResolvedApp(
            groupKey: "bin:\(display.lowercased())",
            displayName: display,
            appBundlePath: nil
        )
    }

    /// Pure path parser: given an executable path, returns the outermost `.app` bundle path.
    /// Example: `/Applications/Google Chrome.app/Contents/Frameworks/.../Google Chrome Helper.app/Contents/MacOS/...`
    ///       -> `/Applications/Google Chrome.app`
    public static func outermostAppBundlePath(forExecutablePath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        var built = ""
        for part in parts {
            built += "/\(part)"
            if part.hasSuffix(".app") && part.count > 4 {
                return built
            }
        }
        return nil
    }

    private static func executablePath(forPID pid: Int) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN (4096 bytes) on macOS
        var buffer = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { ptr in
            ptr.baseAddress.map { String(cString: $0) }
        }
    }

    private static func bundleDisplayName(at bundlePath: String) -> String {
        if let cached = cache.lock.withLock({ cache.bundleNames[bundlePath] }) {
            return cached
        }
        let fallback = URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
        var resolved = fallback
        if let bundle = Bundle(path: bundlePath) {
            if let disp = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !disp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolved = disp
            } else if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolved = name
            }
        }
        cache.lock.withLock {
            if cache.bundleNames.count > 256 {
                cache.bundleNames.removeAll(keepingCapacity: true)
            }
            cache.bundleNames[bundlePath] = resolved
        }
        return resolved
    }
}

/// Maps well-known TCP/UDP port numbers to concise human service badges for outbound connection inspection.
public enum ServicePortCatalog {
    public static func label(forPort port: Int) -> String {
        switch port {
        case 443: return "HTTPS"
        case 80: return "HTTP"
        case 22: return "SSH"
        case 53: return "DNS"
        case 853: return "DoT"
        case 993: return "IMAPS"
        case 995: return "POP3S"
        case 465, 587: return "SMTP"
        case 25: return "SMTP"
        case 5223: return "APNs"
        case 5228: return "Push"
        case 3478, 3479, 19302: return "Call"
        case 5432: return "Postgres"
        case 3306: return "MySQL"
        case 6379: return "Redis"
        case 8080, 8443: return "Alt-HTTP"
        case 3000, 5173: return "Dev"
        case 1194, 51820: return "VPN"
        case 445: return "SMB"
        case 548: return "AFP"
        default: return "TCP"
        }
    }
}
