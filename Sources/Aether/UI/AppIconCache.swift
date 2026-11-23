import AppKit
import SwiftUI

/// Lightweight main-actor icon cache for resolved macOS `.app` bundles.
/// Hits `NSWorkspace.shared.icon(forFile:)` at most once per bundle path per session.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(forBundlePath path: String?, pid: Int = 0) -> NSImage? {
        if let path, !path.isEmpty {
            if let hit = cache[path] {
                return hit
            }
            let img = NSWorkspace.shared.icon(forFile: path)
            img.size = NSSize(width: 32, height: 32)
            if cache.count > 128 {
                cache.removeAll(keepingCapacity: true)
            }
            cache[path] = img
            return img
        }
        if pid > 0,
           let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let bundleURL = app.bundleURL {
            return icon(forBundlePath: bundleURL.path, pid: 0)
        }
        return nil
    }
}

/// Renders a crisp macOS application icon for `.app` bundles, or a clean monochrome
/// daemon/CLI badge for background services (`cloudd`, `CloudTelemetryService`, `git`, `node`).
struct AppProcessIconView: View {
    let appBundlePath: String?
    let pid: Int
    let processName: String
    var size: CGFloat = 16

    private static let cliNames: Set<String> = [
        "curl", "git", "git-remote-https", "ssh", "scp", "rsync", "node",
        "python", "python3", "ruby", "go", "cargo", "swift", "brew", "pnpm", "npm", "bun", "deno"
    ]

    var body: some View {
        if let img = AppIconCache.shared.icon(forBundlePath: appBundlePath, pid: pid) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            let isCLI = Self.cliNames.contains(processName.lowercased())
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Image(systemName: isCLI ? "terminal.fill" : "gearshape.fill")
                    .font(.system(size: size * 0.54, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(width: size, height: size)
        }
    }
}
