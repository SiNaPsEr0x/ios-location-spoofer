import SwiftUI
import NetworkExtension
import os.log

struct ContentView: View {
    @State private var firstSetupCompleted: Bool = UserDefaults.standard.bool(forKey: "firstSetupCompleted")

    var body: some View {
        Group {
            if firstSetupCompleted {
                MapHomeView()
            } else {
                FirstSetupView()
            }
        }
        .onAppear {
            loadVPNManagerIfExists()
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                let newValue = UserDefaults.standard.bool(forKey: "firstSetupCompleted")
                if newValue != firstSetupCompleted {
                    firstSetupCompleted = newValue
                }
            }
        }
    }

    private func loadVPNManagerIfExists() {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                DiagLog.add("[auto-vpn] load managers failed: \(error.localizedDescription)")
                return
            }

            guard let existing = managers?.first else {
                DiagLog.add("[auto-vpn] no existing VPN configuration")
                return
            }

            existing.loadFromPreferences { error in
                if let error = error {
                    DiagLog.add("[auto-vpn] reload manager failed: \(error.localizedDescription)")
                    return
                }

                ContentView.vpnManager = existing
                DiagLog.add("[auto-vpn] manager loaded status=\(existing.connection.status.rawValue)")

                if ContentView.shouldKeepSpoofingActive {
                    ContentView.configureOnDemand(
                        enabled: true,
                        manager: existing
                    ) { _ in
                        ContentView.autoStartVPNIfNeeded(manager: existing)
                    }
                }
            }
        }
    }

    static let autoConnectKey = "spoofingAutoConnectEnabled"

    static var shouldKeepSpoofingActive: Bool {
        let defaults = UserDefaults.standard

        // Migration from builds that existed before the explicit auto-connect flag.
        if defaults.object(forKey: autoConnectKey) == nil {
            let hasSavedLocation =
                !(defaults.string(forKey: "currentLocationName") ?? "").isEmpty
                && LocationConfiguration.shared.currentCoordinates != nil
            defaults.set(hasSavedLocation, forKey: autoConnectKey)
            return hasSavedLocation
        }

        return defaults.bool(forKey: autoConnectKey)
            && LocationConfiguration.shared.currentCoordinates != nil
    }

    static func setSpoofingAutoConnectEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoConnectKey)
        DiagLog.add("[auto-vpn] preference enabled=\(enabled)")
    }

    static func tunnelOptions(latitude: Double, longitude: Double) -> [String: NSObject] {
        [
            "spoofEnabled": NSNumber(value: true),
            "spoofLatitude": NSNumber(value: latitude),
            "spoofLongitude": NSNumber(value: longitude),
        ]
    }

    static func startTunnel(
        manager: NETunnelProviderManager,
        latitude: Double,
        longitude: Double
    ) throws {
        guard let session = manager.connection as? NETunnelProviderSession else {
            throw NSError(
                domain: "LocationSpoofer.Tunnel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "VPN session is not a NETunnelProviderSession"]
            )
        }

        try session.startTunnel(options: tunnelOptions(latitude: latitude, longitude: longitude))
    }

    static func autoStartVPNIfNeeded(manager: NETunnelProviderManager? = ContentView.vpnManager) {
        guard shouldKeepSpoofingActive,
              let coords = LocationConfiguration.shared.currentCoordinates,
              let manager else {
            return
        }

        switch manager.connection.status {
        case .connected, .connecting, .reasserting:
            return
        case .disconnecting:
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                autoStartVPNIfNeeded(manager: manager)
            }
        case .disconnected:
            do {
                try startTunnel(
                    manager: manager,
                    latitude: coords.latitude,
                    longitude: coords.longitude
                )
                DiagLog.add("[auto-vpn] explicit reconnect requested")
            } catch {
                DiagLog.add("[auto-vpn] reconnect failed: \(error.localizedDescription)")
            }
        case .invalid:
            DiagLog.add("[auto-vpn] manager invalid; configuration repair required")
        @unknown default:
            break
        }
    }

    static func configureOnDemand(
        enabled: Bool,
        manager: NETunnelProviderManager? = ContentView.vpnManager,
        completion: ((Error?) -> Void)? = nil
    ) {
        guard let manager else {
            completion?(nil)
            return
        }

        if enabled {
            let connectRule = NEOnDemandRuleConnect()
            connectRule.interfaceTypeMatch = .any
            manager.onDemandRules = [connectRule]
            manager.isOnDemandEnabled = true
            manager.isEnabled = true
        } else {
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
        }

        manager.saveToPreferences { error in
            if let error {
                DiagLog.add("[auto-vpn] save On Demand failed: \(error.localizedDescription)")
                completion?(error)
                return
            }

            manager.loadFromPreferences { reloadError in
                if let reloadError {
                    DiagLog.add("[auto-vpn] reload On Demand failed: \(reloadError.localizedDescription)")
                } else {
                    ContentView.vpnManager = manager
                    DiagLog.add("[auto-vpn] On Demand enabled=\(enabled)")
                }
                completion?(reloadError)
            }
        }
    }

    static func disableAutoConnectAndStop(completion: (() -> Void)? = nil) {
        setSpoofingAutoConnectEnabled(false)

        guard let manager = vpnManager else {
            completion?()
            return
        }

        configureOnDemand(enabled: false, manager: manager) { _ in
            manager.connection.stopVPNTunnel()
            completion?()
        }
    }

    static func installAndStartVPN(
        completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void
    ) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let manager = managers?.first ?? NETunnelProviderManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "dev.duti.location-spoofer.tunnel"
            proto.serverAddress = "192.0.2.1"
            proto.includeAllNetworks = false
            manager.protocolConfiguration = proto
            manager.localizedDescription = "Location Spoofer"
            manager.isEnabled = true

            if shouldKeepSpoofingActive {
                let connectRule = NEOnDemandRuleConnect()
                connectRule.interfaceTypeMatch = .any
                manager.onDemandRules = [connectRule]
                manager.isOnDemandEnabled = true
            } else {
                manager.isOnDemandEnabled = false
                manager.onDemandRules = []
            }

            manager.saveToPreferences { error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                manager.loadFromPreferences { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        ContentView.vpnManager = manager
                        completion(.success(manager))
                    }
                }
            }
        }
    }
}

extension ContentView {
    static var vpnManager: NETunnelProviderManager?
}

#Preview {
    ContentView()
}
