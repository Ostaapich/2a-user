#if DEBUG || SCREEN_TRANSLATION_STAGE0 || SCREEN_TRANSLATION_LIVE
import SwiftUI
import Darwin
import CoreVideo
#if SCREEN_TRANSLATION_PIP_MEDIA
import AVFAudio
#endif

@available(iOS 27.0, *)
final class ProbeModel: ObservableObject {
  @Published var consent = false
  @Published var state = "off"
  @Published var videoCount: UInt64 = 0
  @Published var dimensions = "—"
  @Published var running = false
  @Published var pipReady = false
  @Published private(set) var automaticPiPArmed = false
  private var automaticPiP = AutomaticPiPIntent()
  private var automaticPiPDeadline: DispatchWorkItem?
  private var backgroundRevision: UInt64 = 0
  @Published var protectPiP = false
  @Published var recordQA = false
  @Published var enableOCR = false
  @Published var captureWindow = false
  @Published var captureStyle = "not_selected"
  @Published var viewportPiPAtTop = true
  @Published var navigationTest = false
  @Published var navigationPart = 0
  @Published var navigationParts = 0
  let visualScreen = true
  private let useMockTranslator = true
  @Published var ocrState = "off"
  @Published var translationErrorCode = ""
  @Published var ocrBlocks: [OCRBlock] = []
  @Published var translations: [String: String] = [:]
  @Published var untranslatedBlockIDs: Set<String> = []
  @Published var unplacedBlockCount = 0
  private var failureReasonCounts: [String: Int] = [:]
  private var piPPositionDiagnostics: [String: Any] = [:]
  var onUnauthorized: (() -> Void)?
  private var liveClientFactory: (() -> ScreenTranslationClient?)?
  private var liveClient: ScreenTranslationClient?
  private var translationRetryDeadline: TimeInterval = 0
  private var ocrFrameID: UInt64 = 0
  private var ocrDurationMs: Double = 0
  private var paintingDurationMs: Double = 0
  private var translationDurationMs: Double = 0
  private var translationCacheHits = 0
  private var ocr: ScreenOCRPipeline?
  private var ocrRenderScheduled = false
  private var ocrImage: CVPixelBuffer?
  @Published var expandedBlocks = 0
  @Published var contentScale: Double = 1
  @Published var previousScreen = false
  private var ocrCacheHit = false
  private var ocrRegionArea: Double = 1
  private var renderedOCRFrameID: UInt64 = 0
  @Published var qaState = "off"
  @Published private(set) var pip: SampleBufferPiP
  private let halfScreenLayout: HalfScreenPiPLayout?
  private let gate = SessionGate()
  private var capture: CaptureSource?
  private var observers: [NSObjectProtocol] = []
  private var lastDiagnosticWrite: TimeInterval = 0
  private var readinessDeadline: DispatchWorkItem?
  private var lastStopPiP: [String: Any] = [:]
  private var mediaCleanupErrors: [String] = []
  private var sessionId = ""
  private var sessionStartedAtUptime: TimeInterval?
  private var requestedStopReason = "session_stopped"
  private var captureStopState = "idle"
  #if SCREEN_TRANSLATION_PIP_MEDIA
  private var mediaPlayback: PiPMediaPlaybackLease?
  #endif

  init(halfScreenLayout: HalfScreenPiPLayout? = nil) {
    self.halfScreenLayout = halfScreenLayout
    self.pip = SampleBufferPiP(halfScreenLayout: halfScreenLayout)
    // Remove the explicitly authorized one-block QA sample from the previous build.
    let oldQASample = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ScreenTranslationSingleBlockQA.json")
    try? FileManager.default.removeItem(at: oldQASample)
    if let error = CaptureSource.discardOrphanQA() { state = "qa_orphan_cleanup_failed:\(error)" }
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      self?.ocr?.setAppForeground(false)
      self?.cancelAutomaticPiPDeadline()
      self?.verifyAutomaticPiPAfterBackground()
    })
    observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
      self?.cancelAutomaticPiPDeadline()
      self?.ocr?.setAppForeground(true)
    })
    observers.append(center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() })
    observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() })
    #if SCREEN_TRANSLATION_PIP_MEDIA
    observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
      guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            value == AVAudioSession.InterruptionType.began.rawValue else { return }
      self?.stop(reason: "media_interruption")
    })
    #endif
  }

  func configureLive(clientFactory: @escaping () -> ScreenTranslationClient?) {
    guard !running else { return }
    liveClientFactory = clientFactory
    enableOCR = true; recordQA = false; protectPiP = true; captureWindow = false
  }

  func beginLive() {
    guard liveClientFactory != nil, !running else { return }
    navigationTest = false; recordQA = false; consent = true
    begin()
  }

  private func armAutomaticPiP(token: UUID) {
    // Defer out of readiness/capture callbacks; recheck the session at delivery.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.gate.isCurrent(token), self.running,
            self.automaticPiP.claimArm() else { return }
      self.pip.enableAutomaticStart()
      self.automaticPiPArmed = true
      if UIApplication.shared.applicationState == .background { self.verifyAutomaticPiPAfterBackground() }
      self.recordDiagnostics()
    }
  }

  private func verifyAutomaticPiPAfterBackground() {
    guard automaticPiP.enabled, running, automaticPiP.captureActive, automaticPiPDeadline == nil else { return }
    let expected = sessionId
    let revision = backgroundRevision
    let deadline = DispatchWorkItem { [weak self] in
      guard let self, self.backgroundRevision == revision else { return }
      self.automaticPiPDeadline = nil
      guard self.running, self.sessionId == expected,
            UIApplication.shared.applicationState == .background, !self.pip.isActive else { return }
      self.stop(reason: "pip_automatic_start_unavailable")
    }
    automaticPiPDeadline = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: deadline)
  }

  private func cancelAutomaticPiPDeadline() {
    backgroundRevision &+= 1
    automaticPiPDeadline?.cancel(); automaticPiPDeadline = nil
  }

  var canRetryTranslation: Bool {
    running && ["translation_failed", "translation_timeout", "no_network", "rate_limited", "layout_failed", "layout_partial", "translated_partial"].contains(ocrState) && ProcessInfo.processInfo.systemUptime >= translationRetryDeadline
  }

  func retryTranslation() {
    guard canRetryTranslation else { return }
    ocr?.retryCurrentFrame()
  }

  func begin() {
    guard (consent || navigationTest), !running else { return }
    guard !enableOCR || !recordQA else { state = "ocr_qa_recording_conflict"; return }
    guard !CaptureSource.retryPendingCaptureStop() else { state = "capture_stop_pending"; return }
    guard !CaptureSource.hasPendingQA else { state = "qa_finalization_pending"; return }
    if let error = CaptureSource.discardOrphanQA() { state = "qa_orphan_cleanup_failed:\(error)"; return }
    if !navigationTest, let liveClientFactory {
      guard let client = liveClientFactory() else { state = "auth_required"; return }
      liveClient = client
    }
    let token = gate.begin()
    sessionId = token.uuidString
    sessionStartedAtUptime = ProcessInfo.processInfo.systemUptime
    running = true; state = "permission_required"; videoCount = 0
    automaticPiP.begin(enabled: liveClientFactory != nil && !navigationTest)
    automaticPiPArmed = false
    pipReady = false
    lastStopPiP = [:]
    mediaCleanupErrors = []
    qaState = "off"
    captureStopState = "idle"
    ocrState = liveClientFactory != nil ? "open_other_app" : enableOCR ? "waiting_stability" : "off"
    ocrBlocks = []; translations = [:]; untranslatedBlockIDs = []; unplacedBlockCount = 0; failureReasonCounts = [:]; translationRetryDeadline = 0; ocrFrameID = 0; ocrDurationMs = 0; paintingDurationMs = 0; ocrRenderScheduled = false
    ocrImage = nil; expandedBlocks = 0; contentScale = 1; previousScreen = false; ocrCacheHit = false; ocrRegionArea = 1; renderedOCRFrameID = 0
    #if SCREEN_TRANSLATION_PIP_MEDIA
    do { mediaPlayback = try PiPMediaPlaybackLease() }
    catch {
      let failure = error as NSError
      stop(reason: "pip_media_setup_failed:\(failure.domain):\(failure.code)")
      return
    }
    #endif
    let sessionPiP = SampleBufferPiP(protectCapture: enableOCR || protectPiP, screenAspect: enableOCR && visualScreen && liveClientFactory == nil, halfScreenLayout: halfScreenLayout)
    pip = sessionPiP
    sessionPiP.onState = { [weak self] state in
      guard let self, self.gate.isCurrent(token) else { return }
      self.state = state
      if state == "pip_active" {
        self.cancelAutomaticPiPDeadline()
        self.capture?.setPiPActive(true)
      }
      self.recordDiagnostics()
      if state == "pip_active" && self.recordQA { self.capture?.scheduleQARecording() }
      if state != "pip_active" && state != "pip_not_ready" { self.stop(reason: state) }
    }
    sessionPiP.onReadiness = { [weak self] ready in
      guard let self, self.gate.isCurrent(token) else { return }
      self.pipReady = ready
      self.automaticPiP.ready = ready
      self.armAutomaticPiP(token: token)
      if ready { self.readinessDeadline?.cancel(); self.readinessDeadline = nil }
      self.recordDiagnostics()
    }
    sessionPiP.onClose = { [weak self] in
      guard let self, self.gate.isCurrent(token) else { return }
      self.stop()
    }
    sessionPiP.onNavigationChange = { [weak self] part, count in
      guard let self, self.gate.isCurrent(token) else { return }
      self.navigationPart = part; self.navigationParts = count; self.recordDiagnostics()
    }
    sessionPiP.onNavigationPlaybackChange = { [weak self] playing in
      guard let self, self.gate.isCurrent(token) else { return }
      self.ocr?.setNavigationPaused(!playing)
      self.recordDiagnostics()
    }
    if navigationTest {
      state = "navigation_test"; ocrState = "navigation_test"
      sessionPiP.showNavigationDemo()
      return
    }
    if enableOCR {
      ocr = ScreenOCRPipeline(translationClient: liveClient, navigationEnabled: liveClientFactory != nil) { [weak self] event in
        // Main delivery is serialized with invalidation by the pipeline. Only UI
        // state assignment here: never synchronously stop/reenter the pipeline.
        guard let self, self.gate.isCurrent(token), event.frameID >= self.ocrFrameID else { return }
        if event.state == "unauthorized" || event.state == "access_expired" {
          DispatchQueue.main.async { [weak self] in
            guard let self, self.gate.isCurrent(token) else { return }
            if event.state == "unauthorized" { self.onUnauthorized?() }; self.stop(reason: event.state == "access_expired" ? "session_expired" : event.state)
          }
        }
        self.ocrFrameID = event.frameID
        self.ocrState = event.state
        if !event.errorCode.isEmpty { self.translationErrorCode = event.errorCode }
        else if event.state == "translated" || event.state == "translated_partial" || event.state == "translating" { self.translationErrorCode = "" }
        self.ocrBlocks = event.blocks
        self.translations = event.translations
        self.untranslatedBlockIDs = event.untranslatedBlockIDs
        self.unplacedBlockCount = event.unplacedBlockCount
        self.failureReasonCounts = event.failureReasonCounts
        self.translationRetryDeadline = ProcessInfo.processInfo.systemUptime + event.retryAfterSeconds
        self.ocrDurationMs = event.durationMs
        self.paintingDurationMs = event.paintingDurationMs
        self.translationDurationMs = event.translationDurationMs
        self.translationCacheHits = event.translationCacheHits
        self.ocrImage = event.image
        self.expandedBlocks = event.expandedBlocks
        self.contentScale = event.contentScale
        self.previousScreen = event.previous
        self.ocrCacheHit = event.cacheHit
        self.ocrRegionArea = event.regionArea
        self.scheduleOCRRender(token: token)
        self.recordDiagnostics()
      }
    }
    ocr?.setAppForeground(UIApplication.shared.applicationState != .background)
    captureStyle = "not_selected"
    capture = CaptureSource(token: token, gate: gate, ocr: ocr, captureWindow: captureWindow, halfScreenLayout: halfScreenLayout,
      positionChanged: { [weak self] token, position, mask in
        guard let self, self.gate.isCurrent(token) else { return }
        self.pip.setDetectedPosition(position, mask: mask)
        self.recordDiagnostics()
      }, positionDiagnostics: { [weak self] token, diagnostic in
        guard let self, self.gate.isCurrent(token) else { return }
        self.piPPositionDiagnostics = diagnostic
      }, sourceStyle: { [weak self] token, style in
        guard let self, self.gate.isCurrent(token) else { return }
        self.captureStyle = style; self.recordDiagnostics()
      }, video: { [weak self] token, count, width, height in
      guard let self, self.gate.isCurrent(token) else { return }
      self.videoCount = count
      self.dimensions = "\(width) × \(height)"
      self.renderCurrentFrame()
      let now = ProcessInfo.processInfo.systemUptime
      if now - self.lastDiagnosticWrite >= 1 { self.lastDiagnosticWrite = now; self.recordDiagnostics() }
    }, state: { [weak self] token, state in
      guard let self, self.gate.isCurrent(token) else { return }
      self.state = state
      if state == "capture_started" {
        self.automaticPiP.captureActive = true
        self.armAutomaticPiP(token: token)
        if UIApplication.shared.applicationState == .background { self.verifyAutomaticPiPAfterBackground() }
      }
      self.recordDiagnostics()
      if state == "capture_started" && !self.pipReady {
        let deadline = DispatchWorkItem { [weak self] in
          guard let self, self.gate.isCurrent(token), !self.pipReady else { return }
          self.stop(reason: "pip_not_ready_timeout")
        }
        self.readinessDeadline?.cancel()
        self.readinessDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: deadline)
      }
      if state != "capture_started" { self.stop(reason: state) }
    }, qaState: { [weak self] token, state in
      guard let self else { return }
      guard self.gate.isCurrent(token) || (!self.running && state == "cleanup_failed") else { return }
      self.qaState = state
      self.recordDiagnostics()
      if state == "finished" || state.hasPrefix("failed") || state == "cleanup_failed" { self.stop(reason: "qa_recording_\(state)") }
    }, stopState: { [weak self] token, status in
      guard let self, self.sessionId == token.uuidString else { return }
      self.captureStopState = status
      if !self.running {
        if !self.mediaCleanupErrors.isEmpty { self.state = "media_cleanup_failed" }
        else if status == "stopped" { self.state = self.requestedStopReason }
        else { self.state = status == "failed" ? "capture_stop_failed" : "capture_stopping" }
      }
      self.recordDiagnostics()
    })
    pip.render(videoCount: 0, background: false, displayText: enableOCR ? ocrPreview : nil)
    if let client = liveClient {
      state = "checking_access"
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let outcome = Result { try client.beginSession(sessionID: token, shouldStart: { self?.gate.isCurrent(token) == true }) }
        DispatchQueue.main.async { [weak self] in
          guard let self, self.gate.isCurrent(token), self.running else {
            if case .success = outcome { client.stopSession(sessionID: token) }
            return
          }
          switch outcome {
          case .success:
            guard UIApplication.shared.applicationState == .active else { self.stop(reason: "access_start_interrupted"); return }
            self.state = "permission_required"; self.capture?.request()
          case .failure(let error):
            let typed = error as? ScreenTranslationClientError
            if typed == .unauthorized { self.onUnauthorized?() }
            self.stop(reason: typed == .accessExpired ? "access_expired" : typed == .unauthorized ? "unauthorized" : "access_check_failed")
          }
        }
      }
    } else { capture?.request() }
  }

  func stop(reason: String = "session_stopped") {
    cancelAutomaticPiPDeadline()
    automaticPiP.stop(); automaticPiPArmed = false
    lastStopPiP = pip.diagnostics
    gate.stop()
    if let id = UUID(uuidString: sessionId) { liveClient?.stopSession(sessionID: id) }; ocr?.stop(); ocr = nil; liveClient?.stop(); liveClient = nil; ocrBlocks = []; translations = [:]; untranslatedBlockIDs = []; unplacedBlockCount = 0; failureReasonCounts = [:]; ocrImage = nil; previousScreen = false; ocrState = "stopped"
    readinessDeadline?.cancel(); readinessDeadline = nil
    requestedStopReason = reason
    running = false; consent = false; state = reason
    capture?.stop(); capture = nil
    pip.stop()
    #if SCREEN_TRANSLATION_PIP_MEDIA
    if let mediaPlayback {
      mediaCleanupErrors = mediaPlayback.release()
      self.mediaPlayback = nil
      if !mediaCleanupErrors.isEmpty { state = "media_cleanup_failed" }
    }
    #endif
    pipReady = false
    recordQA = false
    recordDiagnostics()
  }

  private func scheduleOCRRender(token: UUID) {
    guard !ocrRenderScheduled else { return }
    ocrRenderScheduled = true
    // Leave the pipeline's atomic UI-assignment callback before renderer calls:
    // renderer errors may stop the session and reenter pipeline.stop(). One
    // scheduled render uses the latest UI state even if capture becomes idle.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.gate.isCurrent(token), self.running else { return }
      self.ocrRenderScheduled = false
      self.renderCurrentFrame()
    }
  }

  private func renderCurrentFrame() {
    if enableOCR, renderedOCRFrameID != ocrFrameID {
      pip.invalidateScreen()
      renderedOCRFrameID = ocrFrameID
    }
    if enableOCR && visualScreen, let image = ocrImage {
      let pending = ["waiting_stability", "recognizing", "translating"].contains(ocrState)
      let failed = ["translation_failed", "translation_timeout", "no_network", "unauthorized", "rate_limited"].contains(ocrState)
      let badge = pending ? (ocrState == "waiting_stability" ? "Фиксируем новый экран…" : ocrState == "recognizing" ? "Распознаём новый экран…" : "Переводим новый экран…") : failed ? "Не удалось перевести • повторите в 2A" : ocrState == "layout_partial" ? "Не все подписи поместились • повторите в 2A" : ocrState == "translated_partial" ? "Без перевода: \(untranslatedBlockIDs.count) • повтор в 2A" : nil
      if liveClientFactory != nil && !navigationTest {
        pip.renderNavigationSnapshot(image, previous: previousScreen || pending || failed, badgeText: badge, updating: pending,
          completed: !previousScreen && ["translated", "translated_partial", "layout_partial", "no_text"].contains(ocrState))
      } else { pip.renderScreen(image, previous: previousScreen || pending || failed, badgeText: badge) }
    } else {
      pip.render(videoCount: videoCount, background: UIApplication.shared.applicationState == .background,
        displayText: enableOCR ? ocrPreview : nil)
    }
  }

  private var ocrPreview: String {
    let title = liveClientFactory == nil ? "ЛОКАЛЬНЫЙ OCR · НЕ ПЕРЕВОД" : "ПЕРЕВОД ЭКРАНА / 屏幕翻译"
    switch ocrState {
    case "open_other_app", "paused_in_app": return "ПЕРЕВОД ЭКРАНА\nОткройте нужное приложение / 请打开需要翻译的应用"
    case "translating": return "Переводим / 正在翻译"
    case "translation_failed", "translation_timeout", "no_network", "rate_limited": return "Не удалось перевести.\nПовторите в 2A / 请在2A重试"
    case "unauthorized": return "Войдите в 2A повторно / 请重新登录2A"
    case "waiting_stability": return "\(title)\nЖдём остановки экрана…"
    case "recognizing": return "\(title)\nРаспознаём…"
    case "no_text": return "\(title)\nНет текста / 没有文字"
    case "orientation_unavailable": return "\(title)\nНе получена ориентация кадра"
    case "layout_failed": return "Не удалось отобразить снимок.\nПовторите перевод в 2A. / 请在2A重试"
    case "ocr_limit": return "\(title)\nСлишком много текста на экране"
    case "ocr_timeout", "ocr_failed": return "\(title)\nНе удалось распознать.\nОстановите и запустите сессию снова."
    case "recognized": return "МАКЕТ ЭКРАНА / 屏幕演示\nAI ещё не подключён"
    default: return "\(title)\nОжидание кадра…"
    }
  }

  private func recordDiagnostics() {
    // One bounded, content-free QA snapshot in Caches; no image/OCR/token/payload.
    guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
    let snapshot: [String: Any] = ["schemaVersion": 1, "state": state, "running": running,
      "sessionId": sessionId,
      "videoCallbacks": videoCount, "dimensions": dimensions,
      "sessionElapsedMs": sessionStartedAtUptime.map { max(0, (ProcessInfo.processInfo.systemUptime - $0) * 1000) } ?? 0, "pip": pip.diagnostics,
      "pipBeforeStop": lastStopPiP, "piPPositionDetector": piPPositionDiagnostics,
      "backgroundModes": Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? [],
      "pid": ProcessInfo.processInfo.processIdentifier,
      "appState": UIApplication.shared.applicationState.rawValue,
      "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
      "processMemory": Self.processMemory(), "qaState": qaState,
      "mediaCleanupErrors": mediaCleanupErrors, "captureStopState": captureStopState,
      "ocrEnabled": enableOCR, "ocrState": ocrState, "ocrFrameId": ocrFrameID,
      "ocrBlockCount": ocrBlocks.count, "ocrCharacters": ocrBlocks.reduce(0) { $0 + $1.text.count },
      "viewportPiPAtTop": viewportPiPAtTop,
      "liveTranslation": liveClientFactory != nil, "translationErrorCode": translationErrorCode,
      "ocrDurationMs": ocrDurationMs, "paintingDurationMs": paintingDurationMs,
      "translationDurationMs": translationDurationMs, "translationCacheHits": translationCacheHits,
      "untranslatedBlockCount": untranslatedBlockIDs.count, "unplacedBlockCount": unplacedBlockCount, "translationFailureReasons": failureReasonCounts,
      "mockApplied": liveClientFactory == nil && enableOCR && useMockTranslator && !MockScreenTranslator.translateKnownBlocks(ocrBlocks).isEmpty,
      "captureWindowRequested": captureWindow, "captureStyle": captureStyle,
      "visualScreen": visualScreen, "expandedBlocks": expandedBlocks, "contentScale": contentScale,
      "previousScreen": previousScreen, "ocrCacheHit": ocrCacheHit, "ocrRegionArea": ocrRegionArea]
    guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
    try? data.write(to: directory.appendingPathComponent("ScreenTranslationStage0.json"), options: .atomic)
  }

  private static func processMemory() -> [String: UInt64] {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return [:] }
    return ["residentBytes": info.resident_size, "footprintBytes": info.phys_footprint]
  }

  deinit {
    automaticPiPDeadline?.cancel()
    readinessDeadline?.cancel()
    gate.stop()
    ocr?.stop()
    capture?.stop()
    pip.stop()
    #if SCREEN_TRANSLATION_PIP_MEDIA
    mediaPlayback?.release()
    #endif
    observers.forEach(NotificationCenter.default.removeObserver)
  }
}

@available(iOS 27.0, *)
private final class LayerView: UIView {
  let displayLayer: CALayer
  init(_ layer: CALayer) { displayLayer = layer; super.init(frame: .zero); self.layer.addSublayer(layer) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func layoutSubviews() { super.layoutSubviews(); displayLayer.frame = bounds }
}

#if DEBUG || SCREEN_TRANSLATION_STAGE0
@available(iOS 27.0, *)
private struct PiPPreview: UIViewRepresentable {
  let model: ProbeModel
  func makeUIView(context: Context) -> UIView { LayerView(model.pip.layer) }
  func updateUIView(_ uiView: UIView, context: Context) {}
}

@available(iOS 27.0, *)
struct ScreenTranslationProbeView: View {
  @StateObject private var model = ProbeModel()
  @Environment(\.dismiss) private var dismiss
  @State private var showSyntheticCard = false
  var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(model.enableOCR ? "2A • Локальный OCR / 本地识别" : "2A • Screen / PiP • Stage 0").font(.title2)
          Text("Технический стенд. Облачного перевода нет. / 技术测试，无云端翻译。")
          Text("Захватывается экран. Кадры не отправляются. В режиме OCR текст распознаётся на iPhone и хранится только в памяти до остановки. В обычном режиме распознавания нет. QA-запись включается отдельно ниже. Микрофон и аудиоданные не используются. Только синтетический контент. / 不上传。本地OCR仅在设备内识别，停止后清除内存文本。测试录像需另行开启。不使用麦克风和音频数据，仅限测试内容。")
          Toggle("Согласен на локальный тест / 同意本地测试", isOn: $model.consent).disabled(model.running)
          Button("Экран с OCR без записи / 屏幕识别，不录像") { model.enableOCR = true; model.captureWindow = false; model.recordQA = false; model.protectPiP = true }.disabled(model.running)
          Button("Тест: выбор окна / 测试选择窗口") { model.enableOCR = true; model.captureWindow = true; model.recordQA = false; model.protectPiP = true }.disabled(model.running)
          if model.enableOCR {
            Text("Макет: заменяются только известные тестовые фразы. AI ещё не подключён. / 演示仅替换固定测试句子，尚未连接AI。")
            Text("Неизвестный текст показывается как OCR, без перевода. / 其他文字仅识别，不翻译。")
          }
          Button("QA: контрольный ролик без защиты / 无保护测试录像") { model.enableOCR = false; model.protectPiP = false; model.recordQA = true }.disabled(model.running)
          Button("QA: ролик с защитой PiP / 画中画防捕获录像") { model.enableOCR = false; model.protectPiP = true; model.recordQA = true }.disabled(model.running)
          Button("Без записи / 不录像") { model.enableOCR = false; model.recordQA = false; model.protectPiP = false }.disabled(model.running)
          Text(model.recordQA ? (model.protectPiP ? "QA с защитой / 防捕获录像" : "QA без защиты / 无保护录像") : "Запись выключена / 不录像")
          if model.recordQA {
            Text("Только Калькулятор с вымышленными цифрами. Через 4 секунды после запуска PiP начнётся запись 10 секунд в Caches, затем захват остановится. Предыдущий QA-ролик заменяется. Файл копируется только на ваш Mac для проверки, без сервера и облака. / 仅限计算器测试。画中画启动4秒后录制10秒，然后停止。仅本机和您的Mac，不上传云端。")
          }
          Text("Тестовый фоновый режим screen-capture согласован. Работоспособность ещё проверяется. / 已批准测试后台屏幕捕获，功能仍需验证。")
          #if SCREEN_TRANSLATION_PIP_MEDIA
          Text("Согласована playback-сессия для PiP. Звук не воспроизводится, микрофон не используется. / 已批准画中画播放会话。不播放音频，不使用麦克风。")
          #endif
          PiPPreview(model: model).id(ObjectIdentifier(model.pip)).frame(width: model.enableOCR && model.visualScreen ? 107 : nil, height: 190)
          Text("State: \(model.state)\nQA: \(model.qaState)\nPiP ready: \(model.pipReady ? "true" : "false")\nVideo callbacks: \(model.videoCount)\nBuffer: \(model.dimensions)\nEnqueued PiP frames: \(model.pip.rendered)\nPID: \(ProcessInfo.processInfo.processIdentifier)").font(.system(.body, design: .monospaced))
          Button("1. Разрешить захват / 允许捕获") { model.begin() }.disabled(!model.consent || model.running)
          Button("2. Запустить PiP / 开始画中画") { model.pip.start() }.disabled(!model.running || !model.pipReady)
          if model.running && !model.pipReady { Text("PiP пока не готов / 画中画尚未就绪") }
          if model.enableOCR {
            Text("OCR: \(model.ocrState)\nИсточник: \(model.captureStyle)")
            if model.previousScreen { Text("Показан предыдущий экран, обновление продолжается. / 显示上一画面，正在更新。") }
            if model.expandedBlocks > 0 { Text("Весь текст размещён на одной странице, компоновка адаптирована. / 所有文字在同一页，布局已调整。") }
            Button("Открыть тестовую карточку / 打开测试卡片") { showSyntheticCard = true }.disabled(!model.running)
            ForEach(model.ocrBlocks, id: \.id) { block in
              Text(block.text).font(.body)
            }
          }
          Button("Остановить / 停止", role: .destructive) { model.stop() }.disabled(!model.running)
          Button("Вернуться в 2A User / 返回应用") { model.stop(); dismiss() }
          Text("Неподвижный PiP и счётчик enqueue не доказывают фоновые обновления. Нужна видеопроверка. / 静止画中画或入队计数不能证明后台更新。")
        }.padding()
      }
      .fullScreenCover(isPresented: $showSyntheticCard) { SyntheticOCRCardView() }
  }
}

@available(iOS 27.0, *)
private struct SyntheticOCRCardView: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title2) }
          .accessibilityLabel("Закрыть тестовую карточку / 关闭测试卡片")
        Spacer()
        Text("测试商品").font(.title3.bold())
        Spacer()
        Image(systemName: "cart").font(.title2)
      }.padding(20).foregroundStyle(.white).background(.red)
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color.blue.opacity(0.12))
            Image(systemName: "shippingbox.fill").font(.system(size: 90)).foregroundStyle(.blue)
          }.frame(height: 170)
          HStack {
            Text("¥128.50").font(.system(size: 32, weight: .bold)).foregroundStyle(.red)
            Spacer()
            Text("现货").font(.title3)
          }
          ForEach(MockScreenTranslator.fixtures, id: \.0) { item in
            Text(item.0).font(.system(size: 28)).frame(maxWidth: .infinity, alignment: .leading)
          }
          HStack {
            HStack(spacing: 20) { Text("−"); Text("2"); Text("+") }
              .font(.title3).padding(12).background(Color.gray.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer()
            Text("加入购物车").font(.headline).padding(16).foregroundStyle(.white)
              .background(.red).clipShape(RoundedRectangle(cornerRadius: 12))
          }
        }.padding(24)
      }
    }.foregroundStyle(.black).background(.white)
  }
}

#if SCREEN_TRANSLATION_STANDALONE
@main
struct ProbeApp: App {
  var body: some Scene { WindowGroup { ScreenTranslationProbeView() } }
}
#endif
#endif
#endif
