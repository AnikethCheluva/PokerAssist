import MWDATCore
import SwiftUI
import Combine
import MWDATMockDevice

@MainActor
class WearablesManager: ObservableObject {
    @Published var devices: [DeviceIdentifier]
    @Published var hasMockDevice: Bool
    @Published var registrationState: RegistrationState
    @Published var showGettingStartedSheet: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var linkStatus: LinkState = .disconnected

    private var registrationTask: Task<Void, Never>?
    private var deviceStreamTask: Task<Void, Never>?

    private let wearables: WearablesInterface
    private var compatibilityListenerTokens: [DeviceIdentifier: AnyListenerToken] = [:]
    private var linkStateListenerTokens: [DeviceIdentifier: AnyListenerToken] = [:]

    init(wearables: WearablesInterface) {
        self.wearables = wearables
        self.devices = wearables.devices
        self.hasMockDevice = false
        self.registrationState = wearables.registrationState

        // Seed initial link status if a device already exists
        if let firstId = devices.first,
           let device = wearables.deviceForIdentifier(firstId) {
            linkStatus = device.linkState
        }

        registrationTask = Task {
            for await registrationState in wearables.registrationStateStream() {
                let previousState = self.registrationState
                self.registrationState = registrationState

                if self.showGettingStartedSheet == false &&
                    registrationState == .registered &&
                    previousState == .registering {
                    self.showGettingStartedSheet = true
                }

                if registrationState == .registered {
                    await setupDeviceStream()
                } else {
                    // Not registered → treat as disconnected
                    self.linkStatus = .disconnected
                }
            }
        }
    }

    deinit {
        registrationTask?.cancel()
        deviceStreamTask?.cancel()
    }

    private func setupDeviceStream() async {
        if let task = deviceStreamTask, !task.isCancelled {
            task.cancel()
        }

        deviceStreamTask = Task {
            for await devices in wearables.devicesStream() {
                self.devices = devices

                #if DEBUG
                self.hasMockDevice = !MockDeviceKit.shared.pairedDevices.isEmpty
                #endif

                monitorDeviceCompatibility(devices: devices)
                monitorLinkState(devices: devices)
            }
        }
    }

    private func monitorDeviceCompatibility(devices: [DeviceIdentifier]) {
        let deviceSet = Set(devices)
        compatibilityListenerTokens = compatibilityListenerTokens.filter { deviceSet.contains($0.key) }

        for deviceId in devices {
            guard compatibilityListenerTokens[deviceId] == nil else { continue }
            guard let device = wearables.deviceForIdentifier(deviceId) else { continue }

            let deviceName = device.nameOrId()
            let token = device.addCompatibilityListener { [weak self] compatibility in
                guard let self else { return }
                if compatibility == .deviceUpdateRequired {
                    Task { @MainActor in
                        self.showError("Device '\(deviceName)' requires an update to work with this app")
                    }
                }
            }
            compatibilityListenerTokens[deviceId] = token
        }
    }

    // NEW: keep linkStatus always in sync with the most relevant device
    private func monitorLinkState(devices: [DeviceIdentifier]) {
        let deviceSet = Set(devices)
        linkStateListenerTokens = linkStateListenerTokens.filter { deviceSet.contains($0.key) }

        // For now, just track the first device in the list as “active”
        guard let activeId = devices.first,
              let device = wearables.deviceForIdentifier(activeId) else {
            linkStatus = .disconnected
            return
        }

        // If already listening to this device, just ensure we have its current state
        if linkStateListenerTokens[activeId] != nil {
            linkStatus = device.linkState
            return
        }

        // Seed with current state
        linkStatus = device.linkState

        // Listen for changes
        let token = device.addLinkStateListener { [weak self] newState in
            Task { @MainActor in
                self?.linkStatus = newState
            }
        }

        linkStateListenerTokens[activeId] = token
    }

    func registerGlasses() {
        guard registrationState != .registering else { return }
        do {
            try wearables.startRegistration()
        } catch {
            showError(error.description)
        }
    }

    func unregisterGlasses() {
        do {
            try wearables.startUnregistration()
        } catch {
            showError(error.description)
        }
    }

    func showError(_ error: String) {
        errorMessage = error
        showError = true
    }

    func dismissError() {
        showError = false
    }
}

