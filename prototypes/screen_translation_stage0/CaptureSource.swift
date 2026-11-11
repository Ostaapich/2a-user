#if DEBUG || SCREEN_TRANSLATION_STAGE0 || SCREEN_TRANSLATION_LIVE
import CoreMedia
import ImageIO
import ScreenCaptureKit

/// iOS 27 candidate. Recording requires the separate explicit synthetic QA opt-in.
@available(iOS 27.0, *)
final class CaptureSource: NSObject, SCContentSharingPickerObserver, SCStreamDelegate, SCStreamOutput {
  let token: UUID
  private let sessionStartedAtUptime = ProcessInfo.processInfo.systemUptime
  private let gate: SessionGate
  private let ocr: ScreenOCRPipeline?
  private let captureWindow: Bool
  private let halfScreenLayout: HalfScreenPiPLayout?
  private let positionChanged: (UUID, PiPVerticalPosition, OCRBox) -> Void
  private let positionDiagnostics: (UUID, [String: Any]) -> Void
  private var lastPositionDiagnosticTime: TimeInterval = 0
  // All detector state is owned by the serial video queue.
  private var positionDetector = PiPPositionDetector()
  private var lastPiPPosition: PiPVerticalPosition?
  private var lastPiPMask: OCRBox?
  private var detectsPiPPosition = false

  func setPiPActive(_ active: Bool) {
    queue.async { [weak self] in self?.detectsPiPPosition = active }
  }
  private let sourceStyle: (UUID, String) -> Void
  private let queue = DispatchQueue(label: "com.twoalogistic.screenprobe.video", qos: .userInitiated)
  private var stream: SCStream?
  private let video: (UUID, UInt64, Int32, Int32) -> Void
  private let state: (UUID, String) -> Void
  private var acceptingPicker = true
  private let mailbox = LatestMailbox<(UInt64, Int32, Int32)>()
  private let qaState: (UUID, String) -> Void
  private let stopState: (UUID, String) -> Void
  private static var pendingCaptureStop: CaptureSource?
  private var captureStopDeadline: DispatchWorkItem?
  private var captureStopAttempt = 0
  private var qaCancellationSent = false

  /// Explicit restart retries a failed stop; never starts a second capture over it.
  static func retryPendingCaptureStop() -> Bool {
    if let owner = qaWriter {
      if owner.finishQAIfStopped() { return false }
      if owner.qaStopAttempts >= 2 && !owner.qaStopInFlight {
        owner.qaStopAttempts = 0
        owner.requestQAStop()
      }
      return true
    }
    guard let owner = pendingCaptureStop else { return false }
    if owner.stream?.isCapturing != true { owner.finishCaptureStop(); return false }
    if owner.captureStopDeadline == nil {
      owner.captureStopAttempt = 0
      owner.stopCaptureRetainingOwner()
    }
    return true
  }
  private var recording: QAClipWriter?
  // Accessed only on the serial video queue.
  private var qaSampleWriter: QAClipWriter?
  private var qaFrames = 0
  private var qaFinishRequested = false
  private var qaStart: DispatchWorkItem?
  private var qaStop: DispatchWorkItem?
  private var qaScheduled = false
  // Retain an in-flight writer beyond display-session cancellation.
  private static var qaWriter: CaptureSource?
  static var hasPendingQA: Bool { qaWriter != nil }
  private var recordingURL: URL?
  private var qaFinalized = false
  private var qaCancelled = false
  private var qaFailure: String?
  private var qaStopAttempts = 0
  private var qaStopInFlight = false
  private var qaStreamStopped = false
  private var qaStarted = false

  static func discardOrphanQA() -> String? {
    guard qaWriter == nil else { return nil }
    guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return "cache_unavailable" }
    do {
      let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
      let prefix = "ScreenTranslationStage0-QA-", suffix = ".partial.mp4"
      var removed = false
      for file in files {
        let name = file.lastPathComponent
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { continue }
        let id = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        guard UUID(uuidString: id) != nil, try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
        try FileManager.default.removeItem(at: file)
        removed = true
      }
      let resultURL = directory.appendingPathComponent("ScreenTranslationStage0-QA-result.json")
      let oldResult = (try? Data(contentsOf: resultURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      let incomplete = ["countdown", "pending_cleanup"].contains(oldResult?["status"] as? String ?? "")
      if removed || incomplete {
        let result: [String: Any] = ["schemaVersion": 1, "ready": false, "status": "orphan_discarded", "fileName": ""]
        let data = try JSONSerialization.data(withJSONObject: result)
        try data.write(to: resultURL, options: .atomic)
      }
      return nil
    } catch {
      let failure = error as NSError
      return "\(failure.domain):\(failure.code)"
    }
  }

  init(token: UUID, gate: SessionGate, ocr: ScreenOCRPipeline? = nil, captureWindow: Bool = false,
       halfScreenLayout: HalfScreenPiPLayout? = nil,
       positionChanged: @escaping (UUID, PiPVerticalPosition, OCRBox) -> Void = { _, _, _ in },
       positionDiagnostics: @escaping (UUID, [String: Any]) -> Void = { _, _ in },
       sourceStyle: @escaping (UUID, String) -> Void = { _, _ in },
       video: @escaping (UUID, UInt64, Int32, Int32) -> Void,
       state: @escaping (UUID, String) -> Void,
       qaState: @escaping (UUID, String) -> Void = { _, _ in },
       stopState: @escaping (UUID, String) -> Void = { _, _ in }) {
    self.token = token; self.gate = gate; self.ocr = ocr; self.captureWindow = captureWindow; self.halfScreenLayout = halfScreenLayout; self.positionChanged = positionChanged; self.positionDiagnostics = positionDiagnostics; self.sourceStyle = sourceStyle; self.video = video; self.state = state
    self.qaState = qaState; self.stopState = stopState
  }

  func request() {
    let picker = SCContentSharingPicker.shared
    guard picker.isAvailable else { state(token, "capture_unavailable"); return }
    var configuration = SCContentSharingPickerConfiguration()
    configuration.showsMicrophoneControl = false
    configuration.showsCameraControl = false
    picker.configuration = configuration
    picker.add(self)
    picker.isActive = true
    if captureWindow { picker.present(using: .window) } else { picker.present() }
  }

  func stop() {
    ocr?.stop()
    qaStart?.cancel()
    acceptingPicker = false
    let picker = SCContentSharingPicker.shared
    picker.remove(self)
    picker.isActive = false
    if recording != nil {
      qaCancelled = true
      requestQAStop()
      return
    }
    qaStop?.cancel()
    stopCaptureRetainingOwner()
  }

  private func stopCaptureRetainingOwner() {
    guard let stream else { stopState(token, "stopped"); return }
    guard captureStopDeadline == nil else { return }
    Self.pendingCaptureStop = self
    captureStopAttempt += 1
    let attempt = captureStopAttempt
    stopState(token, "stopping")
    let deadline = DispatchWorkItem { [weak self] in
      guard let self, Self.pendingCaptureStop === self,
            self.captureStopAttempt == attempt else { return }
      self.captureStopDeadline = nil
      if !stream.isCapturing { self.finishCaptureStop() }
      else if attempt < 2 { self.stopCaptureRetainingOwner() }
      else { self.stopState(self.token, "failed") }
      // On failure retain the single stream handle. A new explicit start retries
      // its stop, and a later system stop callback releases it. No hidden timer loop.
    }
    captureStopDeadline = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: deadline)
    stream.stopCapture { [weak self] error in
      DispatchQueue.main.async {
        guard let self, Self.pendingCaptureStop === self else { return }
        if error == nil || !stream.isCapturing { self.finishCaptureStop() }
      }
    }
  }

  private func finishCaptureStop() {
    captureStopDeadline?.cancel(); captureStopDeadline = nil
    stream = nil
    if Self.pendingCaptureStop === self { Self.pendingCaptureStop = nil }
    stopState(token, "stopped")
  }

  /// One 10-second local test clip, only after user opt-in and actual PiP start.
  func scheduleQARecording() {
    guard !qaScheduled, gate.isCurrent(token) else { return }
    guard Self.qaWriter == nil else { qaState(token, "failed:writer_busy"); return }
    qaScheduled = true
    writeQAResult(ready: false, status: "countdown")
    qaState(token, "countdown")
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.gate.isCurrent(self.token), self.stream != nil else { return }
      guard Self.qaWriter == nil else { self.qaState(self.token, "failed:writer_busy"); return }
      Self.qaWriter = self
      let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      let url = directory.appendingPathComponent("ScreenTranslationStage0-QA-\(self.token.uuidString).partial.mp4")
      self.recordingURL = url
      let writer = QAClipWriter(url: url) { [weak self] result in
        DispatchQueue.main.async {
          guard let self, Self.qaWriter === self else { return }
          self.qaFinalized = true
          switch result {
          case .success(let frames):
            self.qaFrames = frames
            self.qaStarted = frames > 0
            if frames == 0 { self.qaFailure = "no_frames" }
          case .failure(let error):
            if !self.qaCancelled {
              let failure = error as NSError
              self.qaFailure = "\(failure.domain):\(failure.code)"
            }
          }
          self.requestQAStop()
        }
      }
      self.recording = writer
      self.queue.async { self.qaSampleWriter = writer }
      self.qaState(self.token, "recording")
      let deadline = DispatchWorkItem { [weak self] in self?.requestQAStop() }
      self.qaStop = deadline
      DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: deadline)
    }
    qaStart = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
  }

  private func requestQAStop() {
    guard Self.qaWriter === self else { return }
    if let writer = recording, !qaFinishRequested || (qaCancelled && !qaCancellationSent) {
      qaFinishRequested = true
      let cancelled = qaCancelled
      if cancelled { qaCancellationSent = true }
      queue.async {
        self.qaSampleWriter = nil
        writer.finish(cancelled: cancelled)
      }
    }
    if finishQAIfStopped() { return }
    guard !qaStopInFlight, qaStopAttempts < 2, let stream else { return }
    qaStopInFlight = true
    qaStopAttempts += 1
    qaStop?.cancel()
    let watchdog = DispatchWorkItem { [weak self] in
      guard let self, Self.qaWriter === self else { return }
      self.qaStopInFlight = false
      if self.finishQAIfStopped() { return }
      if self.qaStopAttempts < 2 { self.requestQAStop() }
      else {
        self.qaFailure = self.qaFailure ?? "finalization_timeout"
        self.qaCancelled = true
        // cancelWriting also resolves a finishWriting callback that never arrived.
        // Publication still waits for terminal writer completion + capture stop.
        if !self.qaCancellationSent, let writer = self.recording {
          self.qaCancellationSent = true
          self.queue.async {
            self.qaSampleWriter = nil
            writer.finish(cancelled: true)
          }
        }
        self.writeQAResult(ready: false, status: "pending_cleanup")
        self.qaState(self.token, "cleanup_failed")
      }
    }
    qaStop = watchdog
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: watchdog)
    stream.stopCapture { [weak self] error in
      DispatchQueue.main.async {
        guard let self, Self.qaWriter === self else { return }
        self.qaStopInFlight = false
        if error == nil { self.qaStreamStopped = true }
        if let error, stream.isCapturing {
          let failure = error as NSError
          self.qaFailure = "stop:\(failure.domain):\(failure.code)"
        }
        self.finishQAIfStopped()
      }
    }
  }

  @discardableResult
  private func finishQAIfStopped() -> Bool {
    guard qaFinalized, qaStreamStopped || stream?.isCapturing != true else { return false }
    qaStop?.cancel()
    var ready = !qaCancelled && qaFailure == nil && qaFrames > 0
    if let url = recordingURL {
      do {
        if ready {
          let final = url.deletingLastPathComponent().appendingPathComponent("ScreenTranslationStage0-QA.mp4")
          if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
          try FileManager.default.moveItem(at: url, to: final)
        } else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
      } catch {
        ready = false
        let failure = error as NSError
        qaFailure = "file:\(failure.domain):\(failure.code)"
        try? FileManager.default.removeItem(at: url)
      }
    } else { ready = false }
    let status = ready ? "finished" : qaFailure == nil ? "cancelled" : "failed:\(qaFailure!)"
    writeQAResult(ready: ready, status: status)
    recording = nil
    recordingURL = nil
    stream = nil
    if Self.qaWriter === self { Self.qaWriter = nil }
    qaState(token, status)
    return true
  }

  private func writeQAResult(ready: Bool, status: String) {
    guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
    let result: [String: Any] = ["schemaVersion": 1, "ready": ready, "status": status,
      "sessionId": token.uuidString,
      "errorCode": qaFailure ?? "", "recordingStarted": qaStarted,
      "recordingFinalized": qaFinalized, "stopAcknowledged": qaStreamStopped,
      "streamCapturing": stream?.isCapturing ?? false,
      "recordedFrames": qaFrames,
      "fileName": ready ? "ScreenTranslationStage0-QA.mp4" : "", "sessionElapsedMs": max(0, (ProcessInfo.processInfo.systemUptime - sessionStartedAtUptime) * 1000)]
    guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) else { return }
    try? data.write(to: directory.appendingPathComponent("ScreenTranslationStage0-QA-result.json"), options: .atomic)
  }

  func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.gate.isCurrent(self.token) else { return }
      self.state(self.token, "capture_cancelled")
    }
  }

  func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.gate.isCurrent(self.token) else { return }
      guard self.acceptingPicker else { self.state(self.token, "capture_source_changed"); return }
      self.acceptingPicker = false
      self.sourceStyle(self.token, filter.style == .window ? "window" : filter.style == .display ? "display" : "other")
      guard !filter.isMicrophoneEnabled, !filter.isCameraEnabled else {
        self.state(self.token, "non_video_filter_rejected"); return
      }
      let configuration = SCStreamConfiguration()
      configuration.width = halfScreenLayout?.captureWidth ?? 720
      configuration.height = halfScreenLayout?.captureHeight ?? 1280
      configuration.capturesAudio = false
      let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
      do {
        try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
        self.stream = capture
        capture.startCapture { [weak self, weak capture] error in
          DispatchQueue.main.async {
            guard let self else { capture?.stopCapture { _ in }; return }
            guard self.gate.isCurrent(self.token) else { capture?.stopCapture { _ in }; return }
            self.state(self.token, error == nil ? "capture_started" : "capture_start_failed")
          }
        }
      } catch { self.state(self.token, "capture_output_failed") }
    }
  }

  func contentSharingPickerStartDidFailWithError(_ error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.state(self.token, "picker_failed")
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if Self.pendingCaptureStop === self, !stream.isCapturing { self.finishCaptureStop() }
      if Self.qaWriter === self { self.finishQAIfStopped() }
      self.state(self.token, "capture_stopped")
    }
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    // Audio/microphone are not registered; discard immediately if delivered.
    guard type == .screen else { return }
    autoreleasepool {
      guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer),
            let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            let count = gate.sample(token, now: ProcessInfo.processInfo.systemUptime) else { return }
      qaSampleWriter?.append(sampleBuffer)
      if let image = CMSampleBufferGetImageBuffer(sampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        let number = attachments?.first?[.videoOrientation] as? NSNumber ??
          CMGetAttachment(sampleBuffer, key: SCStreamFrameInfo.videoOrientation.rawValue as CFString, attachmentModeOut: nil) as? NSNumber
        if let raw = number?.uint32Value, let orientation = CGImagePropertyOrientation(rawValue: raw) {
          if detectsPiPPosition, let layout = halfScreenLayout,
             let position = ScreenFrameSampler.pipPosition(image, orientation: orientation,
                expectedAspect: Double(layout.width) / Double(layout.height),
                now: ProcessInfo.processInfo.systemUptime, detector: &positionDetector),
             let mask = positionDetector.confirmedMask,
             position != lastPiPPosition || lastPiPMask.map({ abs($0.y - mask.y) > 0.01 || abs($0.height - mask.height) > 0.01 }) != false {
            lastPiPPosition = position
            lastPiPMask = mask
            // Moving PiP uncovers previously hidden source pixels. Invalidate
            // the old frame before submitting this newly visible content.
            ocr?.retryCurrentFrame()
            DispatchQueue.main.async { [weak self] in
              guard let self, self.gate.isCurrent(self.token) else { return }
              self.positionChanged(self.token, position, mask)
            }
          }
          if detectsPiPPosition {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastPositionDiagnosticTime >= 1 {
              lastPositionDiagnosticTime = now
              let diagnostic = positionDetector.diagnostics
              DispatchQueue.main.async { [weak self] in
                guard let self, self.gate.isCurrent(self.token) else { return }
                self.positionDiagnostics(self.token, diagnostic)
              }
            }
          }
          ocr?.submit(image, orientation: orientation)
        } else { ocr?.orientationUnavailable() }
      }
      let dimensions = CMVideoFormatDescriptionGetDimensions(description)
      guard mailbox.offer((count, dimensions.width, dimensions.height)) else { return }
      // This metadata closure never retains image content; optional OCR owns its bounded image slots.
      DispatchQueue.main.async { [weak self] in
        guard let self, let latest = self.mailbox.take(), self.gate.isCurrent(self.token) else { return }
        self.video(self.token, latest.0, latest.1, latest.2)
      }
    }
  }
}
#endif
