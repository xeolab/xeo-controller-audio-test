import GameController
import SwiftUI

struct ControllerView: View {
    @ObservedObject var probe: ControllerProbe
    @State private var location: ControllerProbe.HapticLocation = .standard
    @State private var pulse: ControllerProbe.Pulse = .transient
    @State private var intensity = 0.7
    @State private var sharpness = 0.45
    @State private var effect: ControllerProbe.TriggerEffect = .vibration
    @State private var start = 0.2
    @State private var amplitude = 0.55
    @State private var frequency = 0.12

    var body: some View {
        Form {
            connectionSection
            triggerInputSection
            hapticsSection
            if let dualSense = probe.dualSense { adaptiveTriggerSection(dualSense) }
        }
        .navigationTitle("手柄测试")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("全部停止", systemImage: "stop.circle", role: .destructive) { probe.stopAll() }
                    .labelStyle(.titleAndIcon)
                    .disabled(probe.controller == nil)
            }
        }
        .onChange(of: probe.selectedID) { location = .standard }
    }

    private var connectionSection: some View {
        Section {
            if let controller = probe.controller {
                if probe.controllers.count > 1 {
                    Picker("当前手柄", selection: Binding(get: { probe.selectedID }, set: { id in
                        if let id { probe.select(id) }
                    })) {
                        ForEach(probe.controllers, id: \.self) { device in
                            Text(device.vendorName ?? device.productCategory).tag(Optional(ObjectIdentifier(device)))
                        }
                    }
                } else {
                    Label(controller.vendorName ?? controller.productCategory, systemImage: "gamecontroller.fill")
                        .font(.headline)
                }
                LabeledContent("系统类别", value: controller.productCategory)
                LabeledContent("可用触觉位置", value: probe.localities.isEmpty ? "未报告" : probe.localities.map(ControllerProbe.localityName).joined(separator: "、"))
                LabeledContent("自适应扳机", value: probe.dualSense == nil ? "未识别" : "已识别")
            } else {
                Label("等待手柄连接", systemImage: "cable.connector")
                    .font(.headline)
            }
            Text(probe.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            Text("设备与状态")
        } footer: {
            Text("验证有线时，在「设置」中关闭蓝牙，再用支持数据的线连接兼容手柄。")
        }
    }

    private var hapticsSection: some View {
        Section {
            if !probe.hapticLocations.isEmpty {
                Picker("振动位置", selection: $location) {
                    ForEach(probe.hapticLocations) { Text($0.rawValue).tag($0) }
                }
                Picker("波形", selection: $pulse) {
                    ForEach(ControllerProbe.Pulse.allCases) { Text($0.rawValue).tag($0) }
                }
                ProbeSlider(title: "强度", value: $intensity)
                ProbeSlider(title: "锐度", value: $sharpness)
                Button("播放触觉", systemImage: "waveform.path") {
                    probe.play(pulse, location: location, intensity: Float(intensity), sharpness: Float(sharpness))
                }
            } else {
                Text("连接支持 Core Haptics 的手柄后可测试。")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("触觉输出 · Core Haptics")
        }
    }

    private var triggerInputSection: some View {
        Section("扳机输入") {
            if probe.controller == nil {
                Text("连接兼容手柄后可测试左右扳机。")
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(ControllerProbe.TriggerSide.allCases) { side in
                            triggerReading(side, input: probe.triggerInput(side))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func triggerReading(_ side: ControllerProbe.TriggerSide, input: GCControllerButtonInput?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let input {
                let value = Double(input.value)
                let position = value.formatted(.percent.precision(.fractionLength(0)))
                let state = input.isPressed ? "按下" : "松开"
                LabeledContent(side.rawValue, value: input.isAnalog ? "\(position) · \(state)" : state)
                    .monospacedDigit()
                if input.isAnalog {
                    ProgressView(value: value)
                        .accessibilityHidden(true)
                }
            } else {
                LabeledContent(side.rawValue, value: "系统未报告输入")
            }
        }
    }

    private func adaptiveTriggerSection(_ dualSense: GCDualSenseGamepad) -> some View {
        Section {
            Picker("效果", selection: $effect) {
                ForEach(ControllerProbe.TriggerEffect.allCases) { Text($0.rawValue).tag($0) }
            }
            ProbeSlider(title: "起始行程", value: $start, range: 0...0.9)
            ProbeSlider(title: effect == .resistance ? "最大阻力" : "最大振幅", value: $amplitude)
            if effect != .resistance { ProbeSlider(title: "相对频率", value: $frequency, range: 0.01...1) }
            HStack(spacing: 12) {
                ForEach(ControllerProbe.TriggerSide.allCases) { armButton($0) }
            }
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                VStack(spacing: 8) {
                    adaptiveReading(.left, trigger: dualSense.leftTrigger)
                    adaptiveReading(.right, trigger: dualSense.rightTrigger)
                }
            }
        } header: {
            Text("自适应扳机 · DualSense")
        } footer: {
            Text("下发效果后扣动对应扳机。每次测试持续 20 秒，可随时全部停止。")
        }
    }

    private func armButton(_ side: ControllerProbe.TriggerSide) -> some View {
        Button {
            probe.arm(side, effect: effect, start: Float(start), amplitude: Float(amplitude), frequency: Float(frequency))
        } label: {
            Text(probe.armed == side ? "已下发 \(side.adaptiveName)" : "下发 \(side.adaptiveName)")
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
    }

    private func adaptiveReading(_ side: ControllerProbe.TriggerSide, trigger: GCDualSenseAdaptiveTrigger) -> some View {
        let status = trigger.mode == .off ? "关闭" : ControllerProbe.triggerStatus(trigger.status)
        return LabeledContent(side.adaptiveName, value: status)
            .font(.subheadline)
    }

}

private struct ProbeSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1

    var body: some View {
        VStack(spacing: 4) {
            LabeledContent(title, value: value.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
            Slider(value: $value, in: range, step: 0.01) { Text(title) }
        }
    }
}
