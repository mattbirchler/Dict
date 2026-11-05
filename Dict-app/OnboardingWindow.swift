import AppKit
import SwiftUI
import os

/// First-run setup: one idea per screen, in the HUD's dark Matrix look.
/// Steps and their rules live in `OnboardingFlow`; this file is the views.
struct OnboardingView: View {
    @Bindable var appState: AppState
    var onComplete: () -> Void
    @State var step: OnboardingStep = .welcome
    @State private var direction: Edge = .trailing

    private var scheme: HUDColorScheme { appState.settings.hudColorScheme }

    static let size = CGSize(width: 600, height: 560)

    private var status: OnboardingStatus {
        OnboardingStatus(
            microphoneGranted: appState.permissionChecker.microphoneGranted,
            speechRecognitionGranted: appState.permissionChecker.speechRecognitionGranted,
            speechRecognitionNeeded: appState.settings.transcriptionEngine.needsSpeechRecognitionPermission,
            accessibilityGranted: appState.permissionChecker.accessibilityGranted,
            engineReady: appState.isEngineReady,
            parakeetReady: appState.isParakeetReady
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressLEDs(current: step, scheme: scheme)
                .padding(.top, 22)
                .padding(.bottom, 8)

            ZStack {
                stepView
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: direction).combined(with: .opacity),
                        removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .clipped()

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            LinearGradient(colors: [scheme.pillTop, scheme.pillBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .tint(scheme.accent)
        .onAppear {
            logStepViewed(step)
            appState.permissionChecker.checkAll()
            appState.refreshEngineReadiness()
            if appState.canAutoPrepare && !appState.isEngineReady && !appState.isPreparingEngine {
                appState.prepareEngine()
            }
        }
        .onChange(of: appState.settings.transcriptionEngine) { _, _ in
            appState.refreshEngineReadiness()
            if appState.canAutoPrepare && !appState.isEngineReady && !appState.isPreparingEngine {
                appState.prepareEngine()
            }
        }
    }

    @ViewBuilder private var stepView: some View {
        switch step {
        case .welcome: WelcomeStep(scheme: scheme)
        case .listen: ListenStep(appState: appState, scheme: scheme)
        case .accessibility: AccessibilityStep(appState: appState, scheme: scheme, onGranted: advance)
        case .chooseKey: ChooseKeyStep(settings: appState.settings, scheme: scheme)
        case .tryIt: TryItStep(appState: appState, scheme: scheme)
        case .accuracy: AccuracyStep(appState: appState, scheme: scheme)
        case .done: DoneStep(settings: appState.settings, scheme: scheme)
        }
    }

    private var footer: some View {
        HStack {
            if let previous = OnboardingFlow.previous(before: step) {
                Button("Back") { go(to: previous, forward: false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(scheme.text.opacity(0.6))
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            Text("\(step.rawValue + 1) OF \(OnboardingFlow.steps.count)")
                .font(HUDFont.label(10.5, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(scheme.accent.opacity(0.7))
            Spacer()
            if step == .done {
                Button("Start Dictating") { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!OnboardingFlow.canContinue(from: step, status: status))
            }
        }
    }

    private func advance() {
        guard let next = OnboardingFlow.next(after: step) else { return }
        go(to: next, forward: true)
    }

    private func go(to target: OnboardingStep, forward: Bool) {
        direction = forward ? .trailing : .leading
        withAnimation(.smooth(duration: 0.3)) { step = target }
        if forward { logStepViewed(target) }
    }

    private func finish() {
        Analytics.shared.log(.onboardingCompleted, properties: [
            "first_run": !appState.hasCompletedOnboarding,
            "engine": appState.settings.transcriptionEngine.rawValue,
        ])
        appState.hasCompletedOnboarding = true
        onComplete()
    }

    /// Only forward moves count, so Back and Continue don't double up the
    /// funnel. `first_run` separates new installs from a replay from the menu.
    private func logStepViewed(_ step: OnboardingStep) {
        Analytics.shared.log(.onboardingStepViewed, properties: [
            "step": Analytics.onboardingStepName(step),
            "first_run": !appState.hasCompletedOnboarding,
        ])
    }
}

// MARK: - Shared pieces

/// One LED per step; lit through the current one.
private struct ProgressLEDs: View {
    var current: OnboardingStep
    var scheme: HUDColorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingFlow.steps) { step in
                Circle()
                    .fill(step.rawValue <= current.rawValue ? scheme.high : scheme.unlit)
                    .frame(width: 6, height: 6)
                    .shadow(color: step.rawValue <= current.rawValue ? scheme.glow.opacity(0.9) : .clear, radius: 3)
            }
        }
        .animation(.easeOut(duration: 0.25), value: current)
    }
}

private struct StepTitle: View {
    var eyebrow: String
    var title: String
    var scheme: HUDColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(HUDFont.label(11, weight: .medium))
                .tracking(1.8)
                .foregroundStyle(scheme.accent)
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(scheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StepBody: View {
    var text: String
    var scheme: HUDColorScheme
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .lineSpacing(3)
            .foregroundStyle(scheme.text.opacity(0.72))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A permission or readiness row: icon, title, one line, then a check or a button.
private struct SetupRow: View {
    var systemImage: String
    var title: String
    var detail: String
    var isDone: Bool
    var scheme: HUDColorScheme
    var buttonTitle = "Allow"
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isDone ? scheme.success : scheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(scheme.text)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(scheme.text.opacity(0.6))
            }
            Spacer()
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(scheme.success)
                    .shadow(color: scheme.success.opacity(0.8), radius: 5)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isDone ? scheme.success.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.2), value: isDone)
    }
}

/// A live dot matrix fed sample speech, for screens that want some life.
private struct SampleMatrix: View {
    var scheme: HUDColorScheme
    var scale: CGFloat = 1.6
    private let started = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 0.085)) { timeline in
            DotMatrix(
                spectrum: HUDPreview.sampleSpectrum(at: timeline.date.timeIntervalSince(started)),
                isLive: true,
                scheme: scheme,
                phase: timeline.date.timeIntervalSinceReferenceDate
            )
            .scaleEffect(scale)
            .frame(width: DotMatrix.width * scale, height: DotMatrix.height * scale)
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var scheme: HUDColorScheme

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            SampleMatrix(scheme: scheme, scale: 2.2)
            VStack(spacing: 10) {
                Text("DICT")
                    .font(HUDFont.label(34, weight: .bold))
                    .tracking(8)
                    .foregroundStyle(scheme.text)
                Text("Hold a key, talk, and the words land where your cursor is.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(scheme.text.opacity(0.85))
                    .multilineTextAlignment(.center)
                Text("Everything is transcribed on this Mac. Nothing you say is sent anywhere.")
                    .font(.system(size: 14))
                    .foregroundStyle(scheme.text.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: 420)
    }
}

private struct ListenStep: View {
    @Bindable var appState: AppState
    var scheme: HUDColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(eyebrow: "Step 1", title: "Let Dict hear you", scheme: scheme)
            StepBody(text: "Dict records only while you hold your key. The audio is transcribed here and never stored.", scheme: scheme)
            SetupRow(
                systemImage: "mic.fill",
                title: "Microphone",
                detail: "To hear what you say",
                isDone: appState.permissionChecker.microphoneGranted,
                scheme: scheme
            ) {
                if appState.permissionChecker.microphoneNotDetermined {
                    Task { await appState.permissionChecker.requestMicrophone() }
                } else {
                    appState.permissionChecker.openMicrophoneSettings()
                }
            }
            if appState.settings.transcriptionEngine.needsSpeechRecognitionPermission {
                SetupRow(
                    systemImage: "waveform.badge.mic",
                    title: "Speech Recognition",
                    detail: "Apple's on-device recognizer turns speech into text",
                    isDone: appState.permissionChecker.speechRecognitionGranted,
                    scheme: scheme
                ) {
                    Task { await appState.permissionChecker.requestSpeechRecognition() }
                }
            }
            Spacer()
        }
        .padding(.top, 24)
        .onAppear {
            if appState.permissionChecker.microphoneNotDetermined {
                Task { await appState.permissionChecker.requestMicrophone() }
            }
        }
    }
}

private struct AccessibilityStep: View {
    @Bindable var appState: AppState
    var scheme: HUDColorScheme
    var onGranted: () -> Void
    @State private var poller: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(eyebrow: "Step 2", title: "Let Dict type for you", scheme: scheme)
            StepBody(text: "Accessibility access lets Dict notice your key in any app and put the words where your cursor is. macOS asks you to switch it on yourself.", scheme: scheme)
            SetupRow(
                systemImage: "hand.raised.fill",
                title: "Accessibility",
                detail: appState.permissionChecker.accessibilityGranted
                    ? "Switched on"
                    : "Turn on Dict in System Settings, then come back",
                isDone: appState.permissionChecker.accessibilityGranted,
                scheme: scheme,
                buttonTitle: "Open System Settings"
            ) {
                appState.permissionChecker.openAccessibilitySettings()
            }
            if !appState.permissionChecker.accessibilityGranted {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Waiting. This screen moves on by itself once it's on.")
                        .font(.system(size: 13))
                        .foregroundStyle(scheme.text.opacity(0.55))
                }
            }
            Spacer()
        }
        .padding(.top, 24)
        .onAppear { startPolling() }
        .onDisappear { poller?.cancel() }
    }

    private func startPolling() {
        poller?.cancel()
        poller = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let wasGranted = appState.permissionChecker.accessibilityGranted
                appState.permissionChecker.checkAccessibility()
                if !wasGranted && appState.permissionChecker.accessibilityGranted {
                    appState.onAccessibilityGranted?()
                    try? await Task.sleep(for: .milliseconds(700))
                    onGranted()
                    return
                }
            }
        }
    }
}

private struct ChooseKeyStep: View {
    @Bindable var settings: SettingsStore
    var scheme: HUDColorScheme
    @State private var monitor: Any?

    private static let keycodes: [Int64: HotkeyChoice] = [54: .rightCommand, 61: .rightOption, 62: .rightControl, 63: .fn]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(eyebrow: "Step 3", title: "Pick your key", scheme: scheme)
            StepBody(text: "Press one of these keys now, or click it. Keys on the right side of the keyboard stay out of the way of shortcuts.", scheme: scheme)
            HStack(spacing: 12) {
                ForEach([HotkeyChoice.fn, .rightControl, .rightOption, .rightCommand], id: \.self) { choice in
                    KeyCap(choice: choice, isSelected: settings.hotkey == choice, scheme: scheme)
                        .onTapGesture { settings.hotkey = choice }
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Text("Or any other key:")
                    .font(.system(size: 13))
                    .foregroundStyle(scheme.text.opacity(0.6))
                ShortcutRecorder(hotkey: $settings.hotkey)
            }
            .frame(maxWidth: .infinity)
            if settings.hotkey == .fn {
                Text("If pressing 🌐 opens the emoji picker, set \u{201C}Press 🌐 key to\u{201D} to \u{201C}Do Nothing\u{201D} in System Settings > Keyboard.")
                    .font(.system(size: 12))
                    .foregroundStyle(scheme.text.opacity(0.5))
            }
            Picker("", selection: $settings.activationMode) {
                ForEach(ActivationMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            StepBody(text: settings.activationMode == .holdToTalk
                 ? "Hold the key while you talk and let go to insert. Tap Space while holding to go hands-free, then press the key again to finish."
                 : "Press the key to start, press it again to stop and insert.", scheme: scheme)
            Spacer()
        }
        .padding(.top, 24)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                // The recorder owns the keyboard while it's listening.
                if !ShortcutRecorder.isRecording, let choice = Self.keycodes[Int64(event.keyCode)] {
                    settings.hotkey = choice
                }
                return event
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private struct KeyCap: View {
    var choice: HotkeyChoice
    var isSelected: Bool
    var scheme: HUDColorScheme

    private var label: String {
        switch choice {
        case .rightCommand: "⌘"
        case .rightOption: "⌥"
        case .rightControl: "⌃"
        case .fn: "fn"
        case .custom: ""
        }
    }

    private var caption: String {
        switch choice {
        case .rightCommand: "Right ⌘"
        case .rightOption: "Right ⌥"
        case .rightControl: "Right ⌃"
        case .fn: "fn / 🌐"
        case .custom: ""
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(isSelected ? scheme.high : scheme.text.opacity(0.8))
                .frame(width: 84, height: 64)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(isSelected ? 0.14 : 0.08), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? scheme.high : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                }
                .shadow(color: isSelected ? scheme.glow.opacity(0.6) : .clear, radius: 10)
            Text(caption)
                .font(HUDFont.label(10.5, weight: .medium))
                .tracking(1)
                .foregroundStyle(isSelected ? scheme.accent : scheme.text.opacity(0.45))
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

private struct TryItStep: View {
    @Bindable var appState: AppState
    var scheme: HUDColorScheme
    @State private var text = ""
    @FocusState private var focused: Bool

    private var succeeded: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(eyebrow: "Step 4", title: "Say something", scheme: scheme)
            if appState.isEngineReady {
                StepBody(text: "Click in the box, hold \(appState.settings.hotkey.glyph) and say anything. Let go and watch.", scheme: scheme)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    StepBody(text: "Getting the speech engine ready. A moment.", scheme: scheme)
                }
            }
            TextEditor(text: $text)
                .font(.system(size: 16))
                .foregroundStyle(scheme.text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 150)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(succeeded ? scheme.success.opacity(0.6) : (focused ? scheme.accent.opacity(0.6) : Color.white.opacity(0.1)), lineWidth: 1.5)
                }
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Your words show up here")
                            .font(.system(size: 16))
                            .foregroundStyle(scheme.text.opacity(0.3))
                            .padding(.top, 12 + 1)
                            .padding(.leading, 12 + 5)
                            .allowsHitTesting(false)
                    }
                }
                .focused($focused)
            if succeeded {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(scheme.success)
                        .shadow(color: scheme.success.opacity(0.8), radius: 5)
                    Text("THAT'S IT. IT WORKS LIKE THIS EVERYWHERE.")
                        .font(HUDFont.label(11.5, weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(scheme.success)
                }
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
            Spacer()
        }
        .padding(.top, 24)
        .animation(.easeOut(duration: 0.25), value: succeeded)
        .onAppear { focused = true }
    }
}

private struct AccuracyStep: View {
    @Bindable var appState: AppState
    var scheme: HUDColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(eyebrow: "Step 5", title: "Want the best accuracy?", scheme: scheme)
            StepBody(text: "Dict is running on Apple's speech engine, which is fast and already on your Mac. Parakeet is a larger model that hears names, jargon and fast talkers better. It runs on this Mac too.", scheme: scheme)
            SetupRow(
                systemImage: "arrow.down.circle.fill",
                title: "Parakeet",
                detail: detail,
                isDone: appState.isParakeetReady,
                scheme: scheme,
                buttonTitle: "Download"
            ) {
                appState.downloadParakeet()
            }
            if appState.isDownloadingParakeet {
                ProgressView(value: appState.parakeetDownloadProgress)
                    .progressViewStyle(.linear)
                StepBody(text: "You can keep going. Dict switches to Parakeet by itself when the download finishes.", scheme: scheme)
            } else if !appState.isParakeetReady {
                StepBody(text: "About 500 MB, once. Skip this and Dict keeps using Apple's engine; you can download Parakeet later in Settings.", scheme: scheme)
            } else {
                StepBody(text: "Parakeet is on and ready.", scheme: scheme)
            }
            Spacer()
        }
        .padding(.top, 24)
    }

    private var detail: String {
        if appState.isParakeetReady { return "Installed and selected" }
        if appState.isDownloadingParakeet { return "Downloading \(Int(appState.parakeetDownloadProgress * 100))%" }
        return "Most accurate, near-instant results"
    }
}

private struct DoneStep: View {
    @Bindable var settings: SettingsStore
    var scheme: HUDColorScheme
    @State private var loginItem = LoginItemManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(eyebrow: "All set", title: "Dict lives in your menu bar", scheme: scheme)
            HStack(spacing: 14) {
                Image(nsImage: MenuBarIcon.image(levels: MenuBarIcon.idleLevels))
                    .renderingMode(.template)
                    .foregroundStyle(scheme.text)
                    .scaleEffect(1.6)
                    .frame(width: 36, height: 30)
                StepBody(text: "Look for the dot grid at the top of your screen. History, settings and this setup are all in there.", scheme: scheme)
            }
            Toggle(isOn: $loginItem.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Dict at login")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(scheme.text)
                    Text("So your key works as soon as you sit down")
                        .font(.system(size: 13))
                        .foregroundStyle(scheme.text.opacity(0.6))
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("ONE TIP")
                    .font(HUDFont.label(11, weight: .medium))
                    .tracking(1.8)
                    .foregroundStyle(scheme.accent)
                StepBody(text: "Tap Space while holding \(settings.hotkey.glyph) to go hands-free for a long dictation. Press \(settings.hotkey.glyph) again to finish, or Escape to throw it away.", scheme: scheme)
            }
            Spacer()
        }
        .padding(.top, 24)
        .onAppear { loginItem.refresh() }
    }
}

// MARK: - Window

final class OnboardingWindowController {
    private var window: NSWindow?
    /// For `--preview-onboarding --snapshot`.
    var windowNumber: Int? { window?.windowNumber }

    func show(appState: AppState, startingAt step: OnboardingStep? = nil) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let start = step ?? OnboardingFlow.firstUnsatisfiedStep(status: OnboardingStatus(
            microphoneGranted: appState.permissionChecker.microphoneGranted,
            speechRecognitionGranted: appState.permissionChecker.speechRecognitionGranted,
            speechRecognitionNeeded: appState.settings.transcriptionEngine.needsSpeechRecognitionPermission,
            accessibilityGranted: appState.permissionChecker.accessibilityGranted
        ))
        let onboardingView = OnboardingView(appState: appState, onComplete: { [weak self] in
            self?.close()
        }, step: start)

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dict Setup"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: OnboardingView.size.width, height: OnboardingView.size.height))
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}
