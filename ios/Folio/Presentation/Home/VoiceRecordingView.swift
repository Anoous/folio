import AVFoundation
import Speech
import SwiftUI

struct VoiceRecordingView: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: RecordingState = .idle
    @State private var transcribedText = ""
    @State private var audioLevels: [CGFloat] = []
    @State private var elapsedSeconds: Int = 0
    @State private var permissionError: String?
    @State private var recordingStartTrigger = false
    @State private var saveTrigger = false

    @State private var audioEngine: AVAudioEngine?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var silenceTimer: Timer?
    @State private var durationTimer: Timer?

    private let maxDuration = 120
    private let silenceThreshold: Float = 0.01
    private let silenceTimeout: TimeInterval = 3.0

    private enum RecordingState {
        case idle
        case recording
        case preview
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch state {
                case .idle:
                    idleContent
                case .recording:
                    recordingContent
                case .preview:
                    previewContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.folio.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "button.cancel", defaultValue: "Cancel")) {
                        stopRecording()
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: recordingStartTrigger)
            .sensoryFeedback(.success, trigger: saveTrigger)
            .onAppear {
                requestPermissionsAndStart()
            }
            .onDisappear {
                stopRecording()
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                handleAudioInterruption(notification)
            }
        }
    }

    // MARK: - Idle Content

    private var idleContent: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            if let error = permissionError {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.folio.textTertiary)
                Text(error)
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text(String(localized: "voice.preparing", defaultValue: "Preparing..."))
                    .font(Typography.body)
                    .foregroundStyle(Color.folio.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Recording Content

    private var recordingContent: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Recording indicator
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(Color.folio.error)
                    .frame(width: 8, height: 8)
                    .modifier(BreathingModifier())
                Text(formattedDuration)
                    .font(.system(size: 17, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.folio.textPrimary)
            }

            // Waveform
            AudioWaveformView(levels: audioLevels)
                .padding(.horizontal, Spacing.screenPadding)

            // Transcribed text (live)
            if !transcribedText.isEmpty {
                ScrollView {
                    Text(transcribedText)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.screenPadding)
                }
                .frame(maxHeight: 120)
            }

            Spacer()

            // Stop button
            Button {
                stopRecordingAndPreview()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.folio.error.opacity(0.15))
                        .frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.folio.error)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - Preview Content

    private var previewContent: some View {
        VStack(spacing: Spacing.md) {
            Text(String(localized: "voice.preview.title", defaultValue: "Transcription"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)

            TextEditor(text: $transcribedText)
                .font(Typography.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.screenPadding)
                .frame(maxHeight: .infinity)

            HStack(spacing: Spacing.sm) {
                // Restart button
                Button {
                    restartRecording()
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15))
                        Text(String(localized: "voice.restart", defaultValue: "Re-record"))
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.folio.echoBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Save button
                Button {
                    saveTranscription()
                } label: {
                    Text(String(localized: "voice.save", defaultValue: "Save"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(canSave ? Color.folio.accent : Color.folio.accent.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canSave)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.md)
        }
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var formattedDuration: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Permissions

    private func requestPermissionsAndStart() {
        // Request microphone first, then speech recognition
        AVAudioApplication.requestRecordPermission { micGranted in
            DispatchQueue.main.async {
                guard micGranted else {
                    permissionError = String(
                        localized: "voice.permission.mic",
                        defaultValue: "Microphone access is required. Please enable it in Settings."
                    )
                    return
                }
                SFSpeechRecognizer.requestAuthorization { speechStatus in
                    DispatchQueue.main.async {
                        guard speechStatus == .authorized else {
                            permissionError = String(
                                localized: "voice.permission.speech",
                                defaultValue: "Speech recognition access is required. Please enable it in Settings."
                            )
                            return
                        }
                        startRecording()
                    }
                }
            }
        }
    }

    // MARK: - Recording

    private func startRecording() {
        // Reset state
        transcribedText = ""
        audioLevels = []
        elapsedSeconds = 0

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            permissionError = String(
                localized: "voice.error.session",
                defaultValue: "Failed to configure audio session."
            )
            return
        }

        guard let speechRecognizer = SFSpeechRecognizer(), speechRecognizer.isAvailable else {
            // Try language-specific recognizers
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            guard let recognizer, recognizer.isAvailable else {
                permissionError = String(
                    localized: "voice.error.unavailable",
                    defaultValue: "Speech recognition is not available on this device."
                )
                return
            }
            beginRecognition(with: recognizer)
            return
        }

        beginRecognition(with: speechRecognizer)
    }

    private func beginRecognition(with speechRecognizer: SFSpeechRecognizer) {
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install audio tap for waveform levels
        var lastSoundTime = Date()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)

            // Compute RMS
            let rms = Self.computeRMS(buffer: buffer)
            let normalized = Self.normalizeRMS(rms)

            DispatchQueue.main.async {
                audioLevels.append(normalized)
                // Keep only the last 40 samples
                if audioLevels.count > 40 {
                    audioLevels.removeFirst(audioLevels.count - 40)
                }

                // Silence detection
                if rms > silenceThreshold {
                    lastSoundTime = Date()
                }
                if Date().timeIntervalSince(lastSoundTime) >= silenceTimeout
                    && state == .recording
                    && !transcribedText.isEmpty
                {
                    stopRecordingAndPreview()
                }
            }
        }

        let task = speechRecognizer.recognitionTask(with: request) { result, error in
            if let result {
                DispatchQueue.main.async {
                    transcribedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                // Recognition ended naturally
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            permissionError = String(
                localized: "voice.error.engine",
                defaultValue: "Failed to start audio recording."
            )
            return
        }

        audioEngine = engine
        recognitionRequest = request
        recognitionTask = task

        state = .recording
        recordingStartTrigger.toggle()

        // Duration timer
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                elapsedSeconds += 1
                if elapsedSeconds >= maxDuration {
                    stopRecordingAndPreview()
                }
            }
        }
        durationTimer = timer
    }

    private func stopRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopRecordingAndPreview() {
        stopRecording()
        withAnimation(Motion.settle) {
            state = .preview
        }
    }

    private func restartRecording() {
        stopRecording()
        withAnimation(Motion.settle) {
            state = .idle
        }
        // Small delay before restarting to let audio session deactivate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            requestPermissionsAndStart()
        }
    }

    private func saveTranscription() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        saveTrigger.toggle()
        onSave(text)
        dismiss()
    }

    // MARK: - Audio Interruption

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        if type == .began && state == .recording {
            stopRecordingAndPreview()
        }
    }

    // MARK: - RMS Computation

    private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }
        return sqrtf(sum / Float(frameLength))
    }

    private static func normalizeRMS(_ rms: Float) -> CGFloat {
        // Map RMS (typically 0.0 ~ 0.5) to 0.0 ~ 1.0 with a curve
        let minDB: Float = -60
        let maxDB: Float = -6
        let db = 20 * log10(max(rms, 1e-6))
        let clamped = max(0, min(1, (db - minDB) / (maxDB - minDB)))
        return CGFloat(clamped)
    }
}

// MARK: - Breathing Animation Modifier

private struct BreathingModifier: ViewModifier {
    @State private var isBreathing = false

    func body(content: Content) -> some View {
        content
            .opacity(isBreathing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear { isBreathing = true }
    }
}
