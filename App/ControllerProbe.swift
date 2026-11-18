import Combine
import CoreHaptics
import Foundation
import GameController

@MainActor
final class ControllerProbe: ObservableObject {
    enum HapticLocation: String, CaseIterable, Identifiable {
        case standard = "默认"
        case both = "双握把"
        case left = "左握把"
        case right = "右握把"
        case triggers = "双扳机"
        case leftTrigger = "左扳机"
        case rightTrigger = "右扳机"

        var id: Self { self }
        var locality: GCHapticsLocality {
            switch self {
            case .standard: return .default
            case .both: return .handles
            case .left: return .leftHandle
            case .right: return .rightHandle
            case .triggers: return .triggers
            case .leftTrigger: return .leftTrigger
            case .rightTrigger: return .rightTrigger
            }
        }
    }

    enum Pulse: String, CaseIterable, Identifiable {
        case transient = "点震"
        case continuous = "持续"
        case triplet = "三连点"

        var id: Self { self }

        func events(intensity: Float, sharpness: Float) -> [CHHapticEvent] {
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ]
            switch self {
            case .transient:
                return [CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: 0)]
            case .continuous:
                return [CHHapticEvent(eventType: .hapticContinuous, parameters: parameters,
                                      relativeTime: 0, duration: 1.2)]
            case .triplet:
                return [0.0, 0.18, 0.36].map {
                    CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: $0)
                }
            }
        }
    }

    enum TriggerSide: String, CaseIterable, Identifiable {
        case left = "左扳机"
        case right = "右扳机"

        var id: Self { self }
        var inputName: String { self == .left ? GCInputLeftTrigger : GCInputRightTrigger }
        var adaptiveName: String { self == .left ? "L2" : "R2" }
    }

    enum TriggerEffect: String, CaseIterable, Identifiable {
        case vibration = "固定振动"
        case ramp = "振幅递增"
        case resistance = "线性阻力"

        var id: Self { self }
    }

    @Published private(set) var controllers: [GCController] = []
    @Published private(set) var selectedID: ObjectIdentifier?
    @Published private(set) var message = "等待手柄连接"
    @Published private(set) var armed: TriggerSide?

    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?
    private var triggerTimeout: Task<Void, Never>?

    init() { refresh() }

    var controller: GCController? {
        controllers.first { ObjectIdentifier($0) == selectedID }
    }

    var dualSense: GCDualSenseGamepad? {
        controller?.extendedGamepad as? GCDualSenseGamepad
    }

    var localities: [GCHapticsLocality] {
        controller?.haptics?.supportedLocalities.sorted { $0.rawValue < $1.rawValue } ?? []
    }

    var hapticLocations: [HapticLocation] {
        guard let haptics = controller?.haptics else { return [] }
        let supported = haptics.supportedLocalities
        return HapticLocation.allCases.filter { $0 == .standard || supported.contains($0.locality) }
    }

    func triggerInput(_ side: TriggerSide) -> GCControllerButtonInput? {
        guard let controller else { return nil }
        return Self.triggerInput(side, on: controller)
    }

    static func triggerInput(_ side: TriggerSide, on controller: GCController) -> GCControllerButtonInput? {
        if let gamepad = controller.extendedGamepad {
            return side == .left ? gamepad.leftTrigger : gamepad.rightTrigger
        }
        return controller.physicalInputProfile.buttons[side.inputName]
    }

    func refresh() {
        let connected = GCController.controllers()
        if let selectedID, !connected.contains(where: { ObjectIdentifier($0) == selectedID }) {
            stopAll(announce: false)
            self.selectedID = nil
        }
        controllers = connected
        if selectedID == nil {
            let preferred = connected.first { controller in
                TriggerSide.allCases.contains { Self.triggerInput($0, on: controller) != nil }
            } ?? connected.first
            if let preferred { select(ObjectIdentifier(preferred)) }
            else { message = "等待手柄连接" }
        }
    }

    func select(_ id: ObjectIdentifier) {
        guard id != selectedID, let candidate = controllers.first(where: { ObjectIdentifier($0) == id }) else { return }
        stopAll(announce: false)
        selectedID = id
        message = "已选中 \(candidate.vendorName ?? candidate.productCategory)"
    }

    func play(_ pulse: Pulse, location: HapticLocation, intensity: Float, sharpness: Float) {
        stopHaptics()
        guard hapticLocations.contains(location), let engine = controller?.haptics?.createEngine(withLocality: location.locality) else {
            message = "当前手柄无法启动「\(location.rawValue)」触觉引擎"
            return
        }
        self.engine = engine
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        do {
            let pattern = try CHHapticPattern(events: pulse.events(intensity: intensity, sharpness: sharpness), parameters: [])
            try engine.start()
            let player = try engine.makePlayer(with: pattern)
            self.player = player
            try player.start(atTime: CHHapticTimeImmediate)
            message = "已发送 \(location.rawValue) · \(pulse.rawValue)"
        } catch {
            stopHaptics()
            message = "触觉播放失败 · \(error.localizedDescription)"
        }
    }

    func arm(_ side: TriggerSide, effect: TriggerEffect, start: Float, amplitude: Float, frequency: Float) {
        guard let dualSense else { return }
        disarm()
        let trigger = side == .left ? dualSense.leftTrigger : dualSense.rightTrigger
        switch effect {
        case .vibration:
            trigger.setModeVibrationWithStartPosition(start, amplitude: amplitude, frequency: frequency)
        case .ramp:
            var positions = GCDualSenseAdaptiveTrigger.PositionalAmplitudes()
            let last = GCDualSenseAdaptiveTrigger.discretePositionCount - 1
            withUnsafeMutableBytes(of: &positions.values) { bytes in
                let values = bytes.bindMemory(to: Float.self)
                for index in 0...last {
                    let travel = Float(index) / Float(last)
                    values[index] = amplitude * max(0, travel - start) / (1 - start)
                }
            }
            trigger.setModeVibration(amplitudes: positions, frequency: frequency)
        case .resistance:
            trigger.setModeSlopeFeedback(startPosition: start, endPosition: 1, startStrength: 0,
                                         endStrength: amplitude)
        }
        armed = side
        message = "已下发 \(side.adaptiveName) · \(effect.rawValue)"
        triggerTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self else { return }
            self.disarm()
            self.message = "扳机已超时关闭"
        }
    }

    func stopAll(announce: Bool = true) {
        stopHaptics()
        disarm()
        if announce { message = "已停止全部振动" }
    }

    private func stopHaptics() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    private func disarm() {
        triggerTimeout?.cancel()
        triggerTimeout = nil
        dualSense?.leftTrigger.setModeOff()
        dualSense?.rightTrigger.setModeOff()
        armed = nil
    }

    static func localityName(_ locality: GCHapticsLocality) -> String {
        switch locality {
        case .default: return "默认"
        case .all: return "全部"
        case .handles: return "双握把"
        case .leftHandle: return "左握把"
        case .rightHandle: return "右握把"
        case .triggers: return "双扳机"
        case .leftTrigger: return "左扳机"
        case .rightTrigger: return "右扳机"
        default: return locality.rawValue
        }
    }

    static func triggerStatus(_ status: GCDualSenseAdaptiveTrigger.Status) -> String {
        switch status {
        case .vibrationNotVibrating: return "等待扣动"
        case .vibrationIsVibrating: return "正在振动"
        case .feedbackNoLoad, .slopeFeedbackReady: return "等待施力"
        case .feedbackLoadApplied, .slopeFeedbackApplyingLoad: return "正在施力"
        case .slopeFeedbackFinished: return "阻力行程结束"
        case .unknown: return "未知"
        default: return "状态 \(status.rawValue)"
        }
    }
}
