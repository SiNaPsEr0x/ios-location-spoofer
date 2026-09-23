//
//  PacketTunnelProvider.swift
//  location-spoofer-tunnel
//
//  Created by Antonio on 10/09/2025.
//

import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {
    private let proxyPort: Int = 8888
    private let proxyHost = "127.0.0.1"
    private let configuration = LocationConfiguration.shared
    private var goLocationSpoofer: GoLocationSpoofer?

    override func startTunnel(
        options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("Tunnel starting...", log: OSLog.default, type: .info)
        goLocationSpoofer = GoLocationSpoofer()
        goLocationSpoofer?.hello()
        let version = goLocationSpoofer?.version() ?? "unknown"
        os_log("Go spoofer library version: %@", log: OSLog.default, type: .info, version)
        var lat: Double?
        var lon: Double?
        var coordinateSource = "app-group fallback"

        if let enabled = options?["spoofEnabled"] as? NSNumber,
           enabled.boolValue,
           let latNumber = options?["spoofLatitude"] as? NSNumber,
           let lonNumber = options?["spoofLongitude"] as? NSNumber {
            lat = latNumber.doubleValue
            lon = lonNumber.doubleValue
            coordinateSource = "start options"

            // Persist as a fallback for starts initiated without explicit options.
            configuration.setCoordinates(latitude: latNumber.doubleValue, longitude: lonNumber.doubleValue)
        } else {
            let coords = configuration.currentCoordinates
            lat = coords?.latitude
            lon = coords?.longitude
        }

        if let lat = lat, let lon = lon {
            os_log(
                "Location spoofing active from %{public}@: %.6f, %.6f",
                log: OSLog.default,
                type: .info,
                coordinateSource,
                lat,
                lon
            )
        } else {
            os_log("No coordinates configured - running in transparent mode", log: OSLog.default, type: .info)
        }
        guard let proxy = goLocationSpoofer, proxy.startProxy(lat: lat, lon: lon) else {
            let error = TunnelError.proxyServerFailed
            os_log("Failed to start Go location spoofing proxy", log: OSLog.default, type: .error)
            completionHandler(error)
            return
        }
        os_log("Go proxy started successfully", log: OSLog.default, type: .info)
        startTunnelWithProxy(completionHandler: completionHandler)
    }

    private func startTunnelWithProxy(completionHandler: @escaping (Error?) -> Void) {
        let tunnelSettings = createTunnelSettings(proxyHost: proxyHost, proxyPort: proxyPort)
        setTunnelNetworkSettings(tunnelSettings) { error in
            if let error = error {
                // A failed tunnel setup must not leave the local proxy listening.
                _ = self.goLocationSpoofer?.stopProxy()
                self.goLocationSpoofer = nil
                os_log("Failed to set tunnel network settings: %@", log: OSLog.default, type: .error, error.localizedDescription)
                completionHandler(error)
            } else {
                os_log("Tunnel started successfully", log: OSLog.default, type: .info)
                completionHandler(nil)
            }
        }
    }

    private func createTunnelSettings(proxyHost: String, proxyPort: Int)
        -> NEPacketTunnelNetworkSettings
    {
        // iOS 27 compatibility: this extension is an HTTP/S proxy, not an IP VPN.
        // Do not claim a default IP route when packetFlow is intentionally unused.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "192.0.2.1")

        let proxySettings = NEProxySettings()
        proxySettings.httpServer = NEProxyServer(address: proxyHost, port: proxyPort)
        proxySettings.httpsServer = NEProxyServer(address: proxyHost, port: proxyPort)
        proxySettings.autoProxyConfigurationEnabled = false
        proxySettings.httpEnabled = true
        proxySettings.httpsEnabled = true
        proxySettings.excludeSimpleHostnames = true

        // Empty-string catch-all is required when the packet tunnel does not claim
        // a default IP route; otherwise HTTP/S clients may bypass the proxy.
        proxySettings.matchDomains = [""]
        proxySettings.exceptionList = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12",
            "127.0.0.1",
            "localhost",
            "*.local",
        ]
        settings.proxySettings = proxySettings

        // A documentation-only /32 address gives the virtual interface a valid
        // non-loopback identity without routing ordinary IP packets into packetFlow.
        let ipv4Settings = NEIPv4Settings(
            addresses: ["192.0.2.2"],
            subnetMasks: ["255.255.255.255"]
        )
        ipv4Settings.includedRoutes = []
        settings.ipv4Settings = ipv4Settings

        // Do not override system DNS. iOS 27 can use multiple network paths
        // (Connectivity Assist); the local HTTP proxy receives host names and
        // resolves its own upstream connections.
        settings.mtu = 1500
        return settings
    }

    override func stopTunnel(
        with reason: NEProviderStopReason, completionHandler: @escaping () -> Void
    ) {
        os_log("Tunnel stopping, reason: %ld", log: OSLog.default, type: .info, reason.rawValue)
        let defaults = UserDefaults(suiteName: "group.dev.duti.location-spoofer")
        defaults?.set(reason.rawValue, forKey: "lastTunnelStopReason")
        defaults?.set(Date().timeIntervalSince1970, forKey: "lastTunnelStopTimestamp")
        if let proxy = goLocationSpoofer {
            if proxy.stopProxy() {
                os_log("Go proxy stopped successfully", log: OSLog.default, type: .info)
            } else {
                os_log("Failed to stop Go proxy", log: OSLog.default, type: .error)
            }
        }
        goLocationSpoofer = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let handler = completionHandler else { return }
        let cmd = String(data: messageData, encoding: .utf8) ?? ""
        switch cmd {
        case "getCoords":
            // Fixed 17-byte response: enabled, latitude and longitude (little endian).
            guard let proxy = goLocationSpoofer,
                  let coords = proxy.getCurrentCoords() else {
                handler(nil)
                return
            }
            var resp = Data()
            resp.append(coords.enabled ? 1 : 0)
            var lat = coords.lat
            var lon = coords.lon
            withUnsafeBytes(of: &lat) { resp.append(contentsOf: $0) }
            withUnsafeBytes(of: &lon) { resp.append(contentsOf: $0) }
            handler(resp)
        case "getLogs":
            guard let proxy = goLocationSpoofer,
                  let logs = proxy.drainGoLogs() else {
                handler(nil)
                return
            }
            handler(Data(logs.utf8))
        default:
            handler(messageData)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    override func wake() {}
}

enum TunnelError: Error {
    case proxyServerFailed
}
