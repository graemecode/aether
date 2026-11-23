import Foundation

// MARK: - LAN Device Model

public struct LANDevice: Identifiable, Sendable, Equatable {
    public var id: String { "\(ip)|\(mac)" }
    public let ip: String
    public let mac: String
    public let vendor: String
    public var hostname: String?
    public let isGateway: Bool
    public let isLocalMac: Bool
    public let isPrivateMAC: Bool

    public init(
        ip: String,
        mac: String,
        vendor: String,
        hostname: String? = nil,
        isGateway: Bool = false,
        isLocalMac: Bool = false,
        isPrivateMAC: Bool = false
    ) {
        self.ip = ip
        self.mac = mac
        self.vendor = vendor
        self.hostname = hostname
        self.isGateway = isGateway
        self.isLocalMac = isLocalMac
        self.isPrivateMAC = isPrivateMAC
    }

    public var displayName: String {
        if isLocalMac { return "This Mac" }
        if let h = hostname, !h.isEmpty, h != ip {
            return h.replacingOccurrences(of: ".local", with: "")
        }
        if isGateway { return vendor == "Unknown" ? "Router / Gateway" : "\(vendor) Gateway" }
        return vendor
    }
}

// MARK: - Compact IEEE OUI Vendor Database (Zero External Files)

public enum OUIVendorLookup {
    public static func vendor(for mac: String) -> String {
        let norm = SystemParsers.normalizeMAC(mac)
        let parts = norm.split(separator: ":")
        guard parts.count >= 3 else { return "Unknown" }

        let prefix = "\(parts[0]):\(parts[1]):\(parts[2])"
        if let exact = table[prefix] {
            return exact
        }
        if SystemParsers.isLocallyAdministeredMAC(norm) == true {
            return "Private / Randomized"
        }
        return "Unknown"
    }

    // Curated high-frequency IEEE OUI prefixes for home, office, and homelab LANs
    private static let table: [String: String] = [
        // Apple
        "00:03:93": "Apple", "00:0a:95": "Apple", "00:1b:63": "Apple", "00:1c:b3": "Apple",
        "00:1e:c2": "Apple", "00:25:00": "Apple", "04:0c:ce": "Apple", "0c:4d:e9": "Apple",
        "14:10:9f": "Apple", "18:af:61": "Apple", "20:c9:d0": "Apple", "28:cf:e9": "Apple",
        "34:36:3b": "Apple", "3c:07:54": "Apple", "40:6c:8f": "Apple", "48:d7:05": "Apple",
        "54:26:96": "Apple", "60:03:08": "Apple", "68:5b:35": "Apple", "70:8c:f2": "Apple",
        "78:31:c1": "Apple", "80:e6:50": "Apple", "88:66:a5": "Apple", "90:72:40": "Apple",
        "98:01:a7": "Apple", "a4:5e:60": "Apple", "a8:20:66": "Apple", "ac:bc:32": "Apple",
        "b8:e8:56": "Apple", "bc:52:b7": "Apple", "c8:2a:14": "Apple", "d0:03:4b": "Apple",
        "d8:30:62": "Apple", "dc:2b:2a": "Apple", "e0:ac:cb": "Apple", "f0:18:98": "Apple",
        "f4:5c:89": "Apple", "f8:1e:df": "Apple",

        // Ubiquiti / UniFi
        "00:15:6d": "Ubiquiti", "00:27:22": "Ubiquiti", "04:18:d6": "Ubiquiti", "18:e8:29": "Ubiquiti",
        "24:5a:4c": "Ubiquiti", "24:a4:3c": "Ubiquiti", "44:d9:e7": "Ubiquiti", "60:22:32": "Ubiquiti",
        "68:72:51": "Ubiquiti", "70:a7:41": "Ubiquiti", "74:83:c2": "Ubiquiti", "78:8a:20": "Ubiquiti",
        "80:2a:a8": "Ubiquiti", "ac:8b:a9": "Ubiquiti", "b4:fb:e4": "Ubiquiti", "d0:21:f9": "Ubiquiti",
        "dc:9f:db": "Ubiquiti", "e0:63:da": "Ubiquiti", "f0:9f:c2": "Ubiquiti", "fc:ec:da": "Ubiquiti",

        // Eero / Amazon
        "18:74:2e": "Amazon", "34:d2:70": "Amazon", "44:65:0d": "Amazon", "50:dc:e7": "Amazon",
        "68:37:e9": "Amazon", "74:c2:46": "Amazon", "84:d6:d0": "Amazon", "a0:02:dc": "Amazon",
        "b0:fc:36": "Eero", "cc:9e:a2": "Eero", "d4:92:5e": "Eero", "f0:27:2d": "Amazon",

        // Google / Nest
        "18:b4:30": "Nest", "1c:f2:9a": "Google", "30:fd:38": "Google", "44:07:0b": "Google",
        "54:60:09": "Google", "64:16:66": "Nest", "94:eb:2c": "Google", "a4:77:33": "Google",
        "d8:eb:46": "Google", "f4:f5:d8": "Google", "f8:0f:f9": "Google",

        // TP-Link / Asus / Netgear / Cisco / MikroTik / Linksys
        "00:1d:0f": "TP-Link", "14:cc:20": "TP-Link", "50:c7:bf": "TP-Link", "60:e3:27": "TP-Link",
        "98:da:c4": "TP-Link", "ac:84:c6": "TP-Link", "b0:be:76": "TP-Link", "c0:25:e9": "TP-Link",
        "d8:0d:17": "TP-Link", "ec:08:6b": "TP-Link", "f4:f2:6d": "TP-Link",
        "04:92:26": "Asus", "08:60:6e": "Asus", "10:c3:7b": "Asus", "2c:56:dc": "Asus",
        "38:d5:47": "Asus", "50:46:5d": "Asus", "60:45:cb": "Asus", "ac:9e:17": "Asus",
        "00:14:6c": "Netgear", "20:4e:7f": "Netgear", "28:c6:8e": "Netgear", "44:94:fc": "Netgear",
        "6c:b0:ce": "Netgear", "84:1b:5e": "Netgear", "a0:40:a0": "Netgear", "c4:04:15": "Netgear",
        "00:0c:29": "VMware", "00:50:56": "VMware", "08:00:27": "VirtualBox",
        "00:1e:13": "Cisco", "00:24:14": "Cisco", "58:bc:27": "Cisco", "cc:46:d6": "Cisco",
        "00:0c:42": "MikroTik", "2c:c8:1b": "MikroTik", "48:8f:5a": "MikroTik", "74:4d:28": "MikroTik",
        "c4:ad:34": "MikroTik", "d4:ca:6d": "MikroTik",

        // Synology / QNAP / Raspberry Pi / Sonos / Espressif / Samsung / Intel
        "00:11:32": "Synology", "90:09:d0": "Synology", "00:08:9b": "QNAP", "24:5e:be": "QNAP",
        "28:cd:c1": "Raspberry Pi", "b8:27:eb": "Raspberry Pi", "d8:3a:dd": "Raspberry Pi", "dc:a6:32": "Raspberry Pi", "e4:5f:01": "Raspberry Pi",
        "00:0e:58": "Sonos", "34:7e:5c": "Sonos", "48:a6:b8": "Sonos", "5c:aa:fd": "Sonos", "78:28:ca": "Sonos", "94:9f:3e": "Sonos", "b8:e9:37": "Sonos",
        "18:fe:34": "Espressif IoT", "24:0a:c4": "Espressif IoT", "30:ae:a4": "Espressif IoT", "5c:cf:7f": "Espressif IoT", "84:cc:a8": "Espressif IoT", "a4:cf:12": "Espressif IoT", "cc:50:e3": "Espressif IoT",
        "00:15:99": "Samsung", "34:23:ba": "Samsung", "50:01:bb": "Samsung", "78:47:1d": "Samsung", "8c:77:12": "Samsung", "b4:3a:28": "Samsung", "cc:07:ab": "Samsung",
        "00:1b:21": "Intel", "3c:a9:f4": "Intel", "68:05:ca": "Intel", "80:86:f2": "Intel", "a4:c4:94": "Intel", "f4:8c:50": "Intel",
        "00:04:20": "Logitech", "b8:27:c5": "LG", "00:09:b0": "Onkyo", "7c:2e:bd": "Google", "00:17:88": "Philips Hue", "ec:b5:fa": "Philips Hue"
    ]
}
