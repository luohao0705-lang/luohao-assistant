import AVFoundation
import Combine
import Speech

@MainActor
final class VoiceInput: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if isRecording { stop(); return }
        errorMessage = nil
        guard await requestPermissions() else { errorMessage = "需要允许麦克风和语音识别权限，才能使用语音交代"; return }
        start()
    }

    func startRecording() async {
        guard !isRecording else { return }
        errorMessage = nil
        guard await requestPermissions() else {
            errorMessage = "需要允许麦克风和语音识别权限，才能使用语音交代"
            return
        }
        start()
    }

    func stopRecording() {
        if isRecording { stop() }
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        return speech && microphone
    }

    private func start() {
        task?.cancel()
        request = SFSpeechAudioBufferRecognitionRequest()
        transcript = ""
        if #available(iOS 16.0, *) {
            request?.addsPunctuation = true
        }
        guard let request, let recognizer, recognizer.isAvailable else { errorMessage = "语音识别服务暂时不可用"; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "无法启动麦克风，请检查系统权限"
            return
        }
        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if error != nil && result == nil {
                    Task { @MainActor in self?.errorMessage = "语音识别中断，请重试" }
                    return
                }
                guard let result else { return }
                Task { @MainActor in self?.transcript = result.bestTranscription.formattedString }
            }
        } catch {
            errorMessage = "麦克风启动失败，请重试"
            stop()
        }
    }

    private func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        request = nil
        task = nil
        isRecording = false
    }
}
