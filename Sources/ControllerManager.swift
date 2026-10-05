import Foundation
import GameController
import Combine

enum ControllerType {
    case xbox
    case playstation
    case unknown
}

enum ControllerDirection {
    case up, down, left, right
}

final class ControllerManager: ObservableObject {
    static let shared = ControllerManager()

    @Published var isConnected = false
    @Published var controllerType: ControllerType = .unknown

    var onAction: (() -> Void)?
    var onDirection: ((ControllerDirection) -> Void)?
    var onCancel: (() -> Void)?
    var onTriangle: (() -> Void)?
    private var suspended = false
    private var connectObserver: Any?
    private var disconnectObserver: Any?

    private init() {
        startMonitoring()
        checkExisting()
    }

    private func startMonitoring() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, !self.suspended,
                  let controller = note.object as? GCController else { return }
            self.bind(controller)
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.suspended else { return }
            if GCController.controllers().isEmpty {
                self.isConnected = false
                self.controllerType = .unknown
            } else if let next = GCController.controllers().first {
                self.bind(next)
            }
        }
        GCController.startWirelessControllerDiscovery {}
    }

    private func checkExisting() {
        if let controller = GCController.controllers().first {
            bind(controller)
        }
    }

    private func bind(_ controller: GCController) {
        isConnected = true
        controllerType = Self.detectType(controller)

        let gp = controller.extendedGamepad

        gp?.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { DispatchQueue.main.async { self?.onAction?() } }
        }

        gp?.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { DispatchQueue.main.async { self?.onCancel?() } }
        }

        gp?.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { DispatchQueue.main.async { self?.onTriangle?() } }
        }

        gp?.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { DispatchQueue.main.async { self?.onDirection?(.up) } }
        }
        gp?.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { DispatchQueue.main.async { self?.onDirection?(.down) } }
        }
        gp?.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { DispatchQueue.main.async { self?.onDirection?(.left) } }
        }
        gp?.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { DispatchQueue.main.async { self?.onDirection?(.right) } }
        }

        gp?.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self else { return }
            let threshold: Float = 0.5
            DispatchQueue.main.async {
                if y > threshold { self.onDirection?(.up) }
                else if y < -threshold { self.onDirection?(.down) }
                if x > threshold { self.onDirection?(.right) }
                else if x < -threshold { self.onDirection?(.left) }
            }
        }
    }

    func suspend() {
        suspended = true
        for controller in GCController.controllers() {
            let gp = controller.extendedGamepad
            gp?.buttonA.pressedChangedHandler = nil
            gp?.buttonB.pressedChangedHandler = nil
            gp?.buttonY.pressedChangedHandler = nil
            gp?.dpad.up.pressedChangedHandler = nil
            gp?.dpad.down.pressedChangedHandler = nil
            gp?.dpad.left.pressedChangedHandler = nil
            gp?.dpad.right.pressedChangedHandler = nil
            gp?.leftThumbstick.valueChangedHandler = nil
        }
        GCController.stopWirelessControllerDiscovery()
        isConnected = false
    }

    func resume() {
        suspended = false
        GCController.startWirelessControllerDiscovery {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.suspended else { return }
            if let controller = GCController.controllers().first {
                self.bind(controller)
            }
        }
    }

    private static func detectType(_ controller: GCController) -> ControllerType {
        let name = (controller.vendorName ?? "").lowercased()
        if name.contains("dualsense") || name.contains("dualshock") || name.contains("playstation") || name.contains("sony") {
            return .playstation
        }
        if name.contains("xbox") || name.contains("microsoft") {
            return .xbox
        }
        return .unknown
    }

    var buttonLabel: String {
        switch controllerType {
        case .playstation: return "\u{2A2F}"  // cross mark ⨯
        case .xbox, .unknown: return "A"
        }
    }
}
