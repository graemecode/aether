import Foundation

/// Lightweight persistent store for per-SSID Trust Zones, pinned AP/gateway fingerprints,
/// and user preferences. Thread-safe via UserDefaults + JSON encoding.
public final class TrustStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    private enum Keys {
        static let menuBarMode = "aether.menuBarMode"
        static let stageMode = "aether.stageMode"
        static let proMode = "aether.proMode"
        static let dismissedOnboarding = "aether.dismissedOnboarding"
        static let hasLaunchedBefore = "aether.hasLaunchedBefore"
        static let trustZones = "aether.trustZones"
        static let fingerprints = "aether.fingerprints"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isProMode: Bool {
        get { lock.withLock { defaults.bool(forKey: Keys.proMode) } }
        set { lock.withLock { defaults.set(newValue, forKey: Keys.proMode) } }
    }

    public var hasDismissedOnboarding: Bool {
        get { lock.withLock { defaults.bool(forKey: Keys.dismissedOnboarding) } }
        set { lock.withLock { defaults.set(newValue, forKey: Keys.dismissedOnboarding) } }
    }

    public var hasLaunchedBefore: Bool {
        get { lock.withLock { defaults.bool(forKey: Keys.hasLaunchedBefore) } }
        set { lock.withLock { defaults.set(newValue, forKey: Keys.hasLaunchedBefore) } }
    }

    public var menuBarMode: MenuBarDisplayMode {
        get {
            lock.withLock {
                guard let raw = defaults.string(forKey: Keys.menuBarMode),
                      let mode = MenuBarDisplayMode(rawValue: raw) else {
                    return .autoSpeed
                }
                return mode
            }
        }
        set {
            lock.withLock {
                defaults.set(newValue.rawValue, forKey: Keys.menuBarMode)
            }
        }
    }

    public var stageMode: StageMode {
        get {
            lock.withLock {
                let raw = defaults.integer(forKey: Keys.stageMode)
                return StageMode(rawValue: raw) ?? .flux
            }
        }
        set {
            lock.withLock {
                defaults.set(newValue.rawValue, forKey: Keys.stageMode)
            }
        }
    }

    public func storedTrustZone(for networkKey: String) -> TrustZone? {
        lock.withLock {
            let map = defaults.dictionary(forKey: Keys.trustZones) as? [String: String] ?? [:]
            guard let raw = map[networkKey] else { return nil }
            return TrustZone(rawValue: raw)
        }
    }

    public func trustZone(for networkKey: String) -> TrustZone {
        storedTrustZone(for: networkKey) ?? .home
    }

    /// Sensible default Trust Zone when the user hasn't explicitly chosen one for a network:
    /// open/WEP Wi-Fi or crowded networks (>= 12 other LAN devices, e.g. airplane, airport, hotel)
    /// default to `.untrusted` (Public); private encrypted networks default to `.home`.
    public static func defaultTrustZone(wifi: WiFiSnapshot, exposure: LANExposureSnapshot) -> TrustZone {
        if wifi.isConnected && wifi.security.isWeak {
            return .untrusted
        }
        if exposure.neighborCount >= 12 {
            return .untrusted
        }
        return .home
    }

    public func resolvedTrustZone(
        for networkKey: String,
        wifi: WiFiSnapshot,
        exposure: LANExposureSnapshot
    ) -> TrustZone {
        storedTrustZone(for: networkKey) ?? Self.defaultTrustZone(wifi: wifi, exposure: exposure)
    }

    public func setTrustZone(_ zone: TrustZone, for networkKey: String) {
        lock.withLock {
            var map = defaults.dictionary(forKey: Keys.trustZones) as? [String: String] ?? [:]
            map[networkKey] = zone.rawValue
            defaults.set(map, forKey: Keys.trustZones)
        }
    }

    public func fingerprint(for ssid: String) -> NetworkFingerprint? {
        lock.withLock {
            loadFingerprintsLocked()[ssid]
        }
    }

    /// Pins a newly observed network or updates lastSeen/BSSID list without overwriting
    /// an anomalous gatewayMAC or downgrading strongestSecurityRank.
    public func observeNetwork(ssid: String, bssid: String?, gatewayMAC: String?, securityRank: Int) -> NetworkFingerprint {
        lock.withLock {
            var all = loadFingerprintsLocked()
            if var existing = all[ssid] {
                if let bssid, !existing.knownBSSIDs.contains(bssid) {
                    existing.knownBSSIDs.append(bssid)
                }
                if existing.gatewayMAC == nil, let gw = gatewayMAC {
                    existing.gatewayMAC = gw
                }
                if securityRank > existing.strongestSecurityRank {
                    existing.strongestSecurityRank = securityRank
                }
                existing.lastSeen = Date()
                all[ssid] = existing
                saveFingerprintsLocked(all)
                return existing
            } else {
                let fp = NetworkFingerprint(
                    ssid: ssid,
                    knownBSSIDs: bssid.map { [$0] } ?? [],
                    gatewayMAC: gatewayMAC,
                    strongestSecurityRank: securityRank,
                    lastSeen: Date()
                )
                all[ssid] = fp
                saveFingerprintsLocked(all)
                return fp
            }
        }
    }

    /// Explicitly trusts the current gateway/security fingerprint (e.g. after router replacement).
    public func trustCurrentFingerprint(ssid: String, bssid: String?, gatewayMAC: String?, securityRank: Int) {
        lock.withLock {
            var all = loadFingerprintsLocked()
            all[ssid] = NetworkFingerprint(
                ssid: ssid,
                knownBSSIDs: bssid.map { [$0] } ?? [],
                gatewayMAC: gatewayMAC,
                strongestSecurityRank: securityRank,
                lastSeen: Date()
            )
            saveFingerprintsLocked(all)
        }
    }

    private func loadFingerprintsLocked() -> [String: NetworkFingerprint] {
        guard let data = defaults.data(forKey: Keys.fingerprints),
              let decoded = try? JSONDecoder().decode([String: NetworkFingerprint].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveFingerprintsLocked(_ map: [String: NetworkFingerprint]) {
        // Cap persisted fingerprints at 100 most recently seen SSIDs to prevent unbounded UserDefaults growth
        let pruned: [String: NetworkFingerprint]
        if map.count > 100 {
            let top = map.values.sorted { $0.lastSeen > $1.lastSeen }.prefix(100)
            pruned = Dictionary(uniqueKeysWithValues: top.map { ($0.ssid, $0) })
        } else {
            pruned = map
        }
        if let data = try? JSONEncoder().encode(pruned) {
            defaults.set(data, forKey: Keys.fingerprints)
        }
    }
}
