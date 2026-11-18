import AVFoundation
import Combine
import GameController
import SwiftUI

@main
struct XEOProbeApp: App {
    var body: some Scene {
        WindowGroup { ProbeTabs() }
    }
}

private struct ProbeTabs: View {
    private enum Tab { case controller, audio }

    @Environment(\.scenePhase) private var phase
    @StateObject private var controller = ControllerProbe()
    @StateObject private var audio = AudioProbe()
    @State private var selectedTab: Tab = .controller

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { ControllerView(probe: controller) }
                .tabItem { Label("手柄", systemImage: "gamecontroller") }
                .tag(Tab.controller)
            NavigationStack { AudioView(probe: audio) }
                .tabItem { Label("音频", systemImage: "waveform") }
                .tag(Tab.audio)
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .audio { controller.stopAll(announce: false) }
            else { audio.stopAndDeactivate() }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active {
                controller.refresh()
                audio.refreshRoute()
            } else if newPhase == .background {
                controller.stopAll(announce: false)
                audio.stopAndDeactivate()
            } else {
                controller.stopAll(announce: false)
            }
        }
        .onReceive(notifications(.GCControllerDidConnect)) { _ in controller.refresh() }
        .onReceive(notifications(.GCControllerDidDisconnect)) { _ in controller.refresh() }
        .onReceive(notifications(AVAudioSession.routeChangeNotification)) { _ in audio.refreshRoute() }
        .onReceive(notifications(AVAudioSession.spatialPlaybackCapabilitiesChangedNotification)) { _ in audio.refreshRoute() }
        .onReceive(notifications(AVAudioSession.interruptionNotification)) { audio.handleInterruption($0) }
        .onReceive(notifications(AVAudioSession.mediaServicesWereResetNotification)) { _ in audio.stopAndDeactivate() }
    }

    private func notifications(_ name: Notification.Name) -> some Publisher<Notification, Never> {
        NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
    }
}
