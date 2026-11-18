import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct AudioView: View {
    @ObservedObject var probe: AudioProbe
    @State private var importing = false

    var body: some View {
        Form {
            samplesSection
            playbackSection
            sourceSection
            outputSection
        }
        .navigationTitle("多声道回放")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie, .mpeg4Movie]) { result in
            switch result {
            case .success(let url): probe.acceptImport(url)
            case .failure(let error): probe.reportImportError(error)
            }
        }
    }

    private var samplesSection: some View {
        Section("测试样本") {
            ForEach(AudioSample.samples + [probe.imported].compactMap { $0 }) { sample in
                Button { probe.select(sample) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sample.title).foregroundStyle(.primary)
                            Text(sample.subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if probe.selected == sample { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    }
                    .frame(minHeight: 41)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(probe.selected == sample ? .isSelected : [])
            }
            Button("从文件导入", systemImage: "folder") { importing = true }
        }
    }

    private var playbackSection: some View {
        Section("播放") {
            HStack(spacing: 12) {
                if probe.state == .playing || probe.state == .loading {
                    Button("暂停", systemImage: "pause.fill") { probe.pause() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(probe.state == .paused ? "继续播放" : "播放", systemImage: "play.fill") { probe.play() }
                        .buttonStyle(.borderedProminent)
                }
                Button("停止", systemImage: "stop.fill") { probe.stop() }
                    .buttonStyle(.bordered)
                    .disabled(probe.state == .idle)
            }
            LabeledContent(probe.state.title, value: probe.elapsed.formatted(.number.precision(.fractionLength(1))) + " s")
                .monospacedDigit()
            if !probe.selected.speakers.isEmpty {
                if let index = probe.speakerIndex {
                    LabeledContent("当前测试声道", value: probe.selected.speakers[index])
                }
                Text(probe.selected.speakers.joined(separator: " → "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let failure = probe.failure { Text(failure).foregroundStyle(.red) }
            Toggle("允许多声道空间化", isOn: $probe.spatialization)
        }
    }

    private var sourceSection: some View {
        Section {
            if probe.selected.isAppleAtmos {
                LabeledContent("已核验片源", value: "EC-3 + JOC · 6 兼容声道 · 48 kHz")
                LabeledContent("HLS 信令", value: "16/JOC（复杂度标记）")
            }
            if probe.sourceFormats.isEmpty {
                Text(probe.state == .idle ? "播放后读取音轨格式。" : "等待系统提供音轨描述。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(probe.sourceFormats, id: \.self) { format in
                    LabeledContent(probe.formatsAreActiveTracks ? "播放器所用音轨" : "资源音轨", value: format)
                }
            }
        } header: {
            Text("片源格式")
        } footer: {
            if probe.selected.isAppleAtmos { Text("Atmos 的对象由播放设备渲染，兼容声道数与最终输出声道数各自独立。") }
        }
    }

    private var outputSection: some View {
        Section {
            if let route = probe.route {
                if route.ports.isEmpty { Text("iOS 暂无输出路由").foregroundStyle(.secondary) }
                ForEach(Array(route.ports.enumerated()), id: \.offset) { _, port in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(port.name).font(.headline)
                        Text("\(port.type) · \(port.channels.map { "\($0) 个描述声道" } ?? "未报告描述声道")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("系统空间音频 · \(port.spatialEnabled ? "可用且开启" : "未开启或不支持")")
                            .font(.subheadline)
                    }
                }
                LabeledContent("当前 / 最大声道", value: "\(route.currentChannels) / \(route.maximumChannels)")
                    .monospacedDigit()
                if route.sampleRate > 0 { LabeledContent("会话采样率", value: "\(route.sampleRate) Hz") }
                LabeledContent("系统输出节点", value: route.outputFormat ?? "未报告格式")
                Text(route.assessment).font(.subheadline)
            }
            Button(probe.route == nil ? "读取当前输出" : "刷新输出读数", systemImage: "arrow.clockwise") {
                probe.inspectRoute()
            }
        } header: {
            Text("当前输出设备")
        } footer: {
            Text("输出节点显示 iOS 的音频设备格式。USB、蓝牙或 HDMI 的线缆编码和接收端实际解码格式需从外设确认。")
        }
    }
}
