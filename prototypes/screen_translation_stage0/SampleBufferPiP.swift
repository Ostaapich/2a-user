#if DEBUG || SCREEN_TRANSLATION_STAGE0 || SCREEN_TRANSLATION_LIVE
import AVKit
import UIKit

#if SCREEN_TRANSLATION_PIP_MEDIA
/// Public PiP media configuration, only in an explicitly approved test build.
/// No audio samples, player, microphone or recording API are created.
@available(iOS 27.0, *)
final class PiPMediaPlaybackLease {
  private let session = AVAudioSession.sharedInstance()
  private let previousCategory: AVAudioSession.Category
  private let previousMode: AVAudioSession.Mode
  private let previousOptions: AVAudioSession.CategoryOptions
  private var activated = false

  init() throws {
    previousCategory = session.category
    previousMode = session.mode
    previousOptions = session.categoryOptions
    do {
      try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
      try session.setActive(true)
      activated = true
    } catch {
      try? session.setCategory(previousCategory, mode: previousMode, options: previousOptions)
      throw error
    }
  }

  @discardableResult
  func release() -> [String] {
    guard activated else { return [] }
    activated = false
    var errors: [String] = []
    do { try session.setActive(false, options: .notifyOthersOnDeactivation) }
    catch { let e = error as NSError; errors.append("deactivate:\(e.domain):\(e.code)") }
    do { try session.setCategory(previousCategory, mode: previousMode, options: previousOptions) }
    catch { let e = error as NSError; errors.append("restore:\(e.domain):\(e.code)") }
    return errors
  }

  deinit { release() }
}
#endif

@available(iOS 27.0, *)
final class SampleBufferPiP: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
  let layer = AVSampleBufferDisplayLayer()
  private var controller: AVPictureInPictureController?
  private let synchronizer = AVSampleBufferRenderSynchronizer()
  private var receiver: AVSampleBufferVideoRenderer.Receiver!
  private var readiness: NSKeyValueObservation?
  var onState: ((String) -> Void)?
  var onReadiness: ((Bool) -> Void)?
  var onClose: (() -> Void)?
  private var frameNumber: Int64 = 0
  private(set) var rendered = 0
  private var lastBufferIOSurface = false
  private var pendingSample: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>?
  private var enqueueTask: Task<Void, Never>?
  private var enqueueGeneration: UInt64 = 0
  private let halfScreenLayout: HalfScreenPiPLayout?
  private var detectedPosition: PiPVerticalPosition?
  private var displayedPosition: PiPVerticalPosition?
  private var detectedMask: OCRBox?
  private var displayedMask: OCRBox?
  private var halfScreenPaused = false
  var progressLabel = "Переводим…"

  func setDetectedPosition(_ position: PiPVerticalPosition, mask: OCRBox) {
    // A newly uncovered half is accepted only with a completed fresh snapshot.
    // Do not replace it immediately with the formerly occluded cached half.
    detectedPosition = position
    detectedMask = mask
  }
  private var navigationSize: CGSize {
    guard let layout = halfScreenLayout else { return CGSize(width: 960, height: 540) }
    return CGSize(width: layout.width, height: layout.height)
  }
  var previewAspectRatio: CGFloat {
    CGFloat(contentWidth) / CGFloat(max(1, contentHeight))
  }
  private var contentWidth = 960
  private var contentHeight = 540
  private var badgedInput: CVPixelBuffer?
  private var badgedOutput: CVPixelBuffer?
  private var badgeLabel = ""
  private var pipRenderSize = CMVideoDimensions(width: 0, height: 0)
  private var navigationFrames: [CVPixelBuffer] = []
  private var navigationTimer: Timer?
  private var navigationPaused = false
  private var navigationSkipCount = 0
  private var navigationPage = -1
  var onNavigationChange: ((Int, Int) -> Void)?
  var onNavigationPlaybackChange: ((Bool) -> Void)?
  private var navigationSource: CVPixelBuffer?
  private var navigationSourceBadge = ""
  private var navigationSourceUpdating = false
  private var navigationPageCount: Int { navigationFrames.count }

  func renderNavigationSnapshot(_ image: CVPixelBuffer, previous: Bool, badgeText: String?, updating: Bool = false, completed: Bool = false) {
    let badge = badgeText ?? (previous ? "Предыдущий снимок" : "")
    let nextPosition = halfScreenLayout != nil && completed ? detectedPosition : displayedPosition
    let nextMask = halfScreenLayout != nil && completed ? detectedMask : displayedMask
    let positionChanged = nextPosition != displayedPosition || nextMask != displayedMask
    guard navigationSource !== image || navigationSourceBadge != badge || navigationSourceUpdating != updating || positionChanged else { return }
    guard !navigationPaused, var parts = ScreenFrameSampler.snapshotParts(image, halfScreen: halfScreenLayout != nil) else { return }
    if halfScreenLayout != nil, let position = nextPosition, let mask = nextMask {
      guard let visibleBox = PiPVisibleRegion.box(position: position, mask: mask),
            let visible = ScreenFrameSampler.cropped(image, orientation: .up, box: visibleBox) else { return }
      parts[position == .top ? 1 : 0] = visible
    }
    var frames: [CVPixelBuffer] = []
    for (index, part) in parts.enumerated() {
      guard let scaled = try? ScreenFramePainter.paint(source: part, orientation: .up,
        blocks: [], translations: [:], pageSize: navigationSize, preserveLayout: true) else {
        onState?("render_buffer_failed"); return
      }
      let frame = scaled.image
      decorateNavigationFrame(frame, index: index, total: parts.count, badge: badge, updating: updating)
      frames.append(frame)
    }
    displayedPosition = nextPosition
    displayedMask = nextMask
    navigationSource = image; navigationSourceBadge = badge; navigationSourceUpdating = updating
    presentNavigationFrames(frames, preservingPosition: !navigationFrames.isEmpty)
  }


  private var navigationDuration: Double { Double(navigationPageCount) * SnapshotViewportPages.secondsPerPage }

  private func decorateNavigationFrame(_ frame: CVPixelBuffer, index: Int, total: Int, badge: String, updating: Bool) {
    // Live PiP only gets a compact progress pill; the old image stays clear.
    guard halfScreenLayout == nil || updating else { return }
    let width = CVPixelBufferGetWidth(frame), height = CVPixelBufferGetHeight(frame)
    let scale = CGFloat(width) / 960
    CVPixelBufferLockBaseAddress(frame, [])
    if let context = CGContext(data: CVPixelBufferGetBaseAddress(frame), width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(frame), space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
      context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
      UIGraphicsPushContext(context)
      if halfScreenLayout != nil {
        let label = progressLabel as NSString
        let font = UIFont.systemFont(ofSize: 26 * scale, weight: .medium)
        let textSize = label.size(withAttributes: [.font: font])
        let pillHeight = 46 * scale
        let pillWidth = textSize.width + 58 * scale
        let pill = CGRect(x: CGFloat(width) - pillWidth - 16 * scale, y: 14 * scale,
          width: pillWidth, height: pillHeight)
        context.setFillColor(UIColor(white: 0.12, alpha: 0.82).cgColor)
        context.addPath(UIBezierPath(roundedRect: pill, cornerRadius: pillHeight / 2).cgPath)
        context.fillPath()
        context.setFillColor(UIColor.systemOrange.cgColor)
        context.fillEllipse(in: CGRect(x: pill.minX + 15 * scale, y: pill.midY - 5 * scale,
          width: 10 * scale, height: 10 * scale))
        label.draw(at: CGPoint(x: pill.minX + 35 * scale, y: pill.midY - textSize.height / 2),
          withAttributes: [.font: font, .foregroundColor: UIColor.white])
      } else if updating {
        context.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(UIColor(red: 0.07, green: 0.12, blue: 0.22, alpha: 0.97).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: min(CGFloat(height), 108 * scale)))
        context.setFillColor(UIColor.systemOrange.cgColor)
        context.fillEllipse(in: CGRect(x: 24 * scale, y: 24 * scale, width: 18 * scale, height: 18 * scale))
        (badge as NSString).draw(at: CGPoint(x: 60 * scale, y: 13 * scale), withAttributes: [
        .font: UIFont.systemFont(ofSize: 32 * scale, weight: .bold), .foregroundColor: UIColor.white])
        ("Показан предыдущий перевод • \(index + 1)/\(total)" as NSString).draw(at: CGPoint(x: 60 * scale, y: 60 * scale), withAttributes: [
        .font: UIFont.systemFont(ofSize: 24 * scale), .foregroundColor: UIColor(white: 1, alpha: 0.8)])
      } else {
        let part = halfScreenLayout == nil ? "\(index + 1)/\(total)" : index == 0 ? "Верхняя половина" : "Нижняя половина"
        let label = badge.isEmpty ? part : "\(part) • \(badge)"
        let size = (label as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 22 * scale, weight: .semibold)])
        context.setFillColor(UIColor(white: 1, alpha: 0.94).cgColor)
        context.fill(CGRect(x: 8 * scale, y: 6 * scale, width: min(CGFloat(width) - 16 * scale, size.width + 20 * scale), height: 38 * scale))
        (label as NSString).draw(at: CGPoint(x: 18 * scale, y: 12 * scale), withAttributes: [
        .font: UIFont.systemFont(ofSize: 22 * scale, weight: .semibold), .foregroundColor: UIColor.darkGray])
      }
      UIGraphicsPopContext()
    }
    CVPixelBufferUnlockBaseAddress(frame, [])
  }

  func showNavigationDemo() {
    let count = halfScreenLayout == nil ? 4 : 2
    let width = Int(navigationSize.width), height = Int(navigationSize.height)
    var frames: [CVPixelBuffer] = []
    for index in 0..<count {
      var buffer: CVPixelBuffer?
      guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary, &buffer) == kCVReturnSuccess,
        let buffer else { onState?("render_buffer_failed"); return }
      CVPixelBufferLockBaseAddress(buffer, [])
      guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
        CVPixelBufferUnlockBaseAddress(buffer, []); return
      }
      let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple]
      context.setFillColor(colors[index].cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
      UIGraphicsPushContext(context)
      let label = "ЧАСТЬ \(index + 1) ИЗ \(count)\nНазад / вперёд — соседняя часть"
      (label as NSString).draw(in: CGRect(x: 45, y: 110, width: max(1, width - 90), height: max(1, height - 150)), withAttributes: [
        .font: UIFont.systemFont(ofSize: 48, weight: .bold), .foregroundColor: UIColor.white])
      UIGraphicsPopContext(); CVPixelBufferUnlockBaseAddress(buffer, [])
      frames.append(buffer)
    }
    presentNavigationFrames(frames)
  }

  func presentNavigationFrames(_ frames: [CVPixelBuffer], preservingPosition: Bool = false) {
    guard !frames.isEmpty, frames.count <= 8 else { return }
    if halfScreenLayout != nil {
      navigationTimer?.invalidate(); navigationTimer = nil
      navigationFrames = frames
      navigationPaused = halfScreenPaused
      navigationPage = displayedPosition == .top ? min(1, frames.count - 1) : 0
      controller?.requiresLinearPlayback = true
      enqueueGeneration += 1; pendingSample = nil; enqueueTask?.cancel(); enqueueTask = nil
      receiver.flush()
      synchronizer.setRate(halfScreenPaused ? 0 : 1, time: .zero)
      enqueue(frames[navigationPage])
      // Keep a live sample source while the translated image is unchanged.
      // This repeats the same selected half; it never advances a page or OCR.
      navigationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        guard let self, !self.halfScreenPaused, self.navigationFrames.indices.contains(self.navigationPage) else { return }
        self.enqueue(self.navigationFrames[self.navigationPage])
      }
      onNavigationChange?(navigationPage, frames.count)
      controller?.invalidatePlaybackState()
      return
    }
    let oldTime = preservingPosition ? navigationSeconds() : 0
    navigationTimer?.invalidate()
    navigationFrames = frames; navigationPaused = false; navigationPage = -1
    controller?.requiresLinearPlayback = false
    let oldPage = Int(oldTime / SnapshotViewportPages.secondsPerPage)
    let position = oldPage < navigationPageCount ? oldTime : Double(navigationPageCount - 1) * SnapshotViewportPages.secondsPerPage
    synchronizer.setRate(1, time: CMTime(seconds: position, preferredTimescale: 600))
    queueNavigationFrames()
    navigationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.updateNavigationState()
    }
    updateNavigationState(refreshQueue: false); controller?.invalidatePlaybackState()
  }

  private func navigationSeconds() -> Double {
    let seconds = synchronizer.currentTime().seconds
    let value = seconds.isFinite ? max(0, seconds) : 0
    if !navigationFrames.isEmpty, value >= navigationDuration {
      let notify = !navigationPaused
      navigationPaused = true
      synchronizer.setRate(0, time: CMTime(seconds: navigationDuration - 0.01, preferredTimescale: 600))
      if notify {
        let expectedFrame = navigationFrames.first
        DispatchQueue.main.async { [weak self] in
          guard let self, self.navigationFrames.first === expectedFrame, self.navigationPaused else { return }
          self.controller?.invalidatePlaybackState()
          self.onNavigationPlaybackChange?(false)
        }
      }
      return navigationDuration - 0.01
    }
    return value
  }

  private func updateNavigationState(refreshQueue: Bool = true) {
    guard !navigationFrames.isEmpty else { return }
    let page = min(navigationPageCount - 1, Int(navigationSeconds() / SnapshotViewportPages.secondsPerPage))
    if page != navigationPage {
      navigationPage = page
      if refreshQueue { queueNavigationFrames() }
      onNavigationChange?(page, navigationPageCount)
      controller?.invalidatePlaybackState()
    }
  }

  private func queueNavigationFrames() {
    enqueueGeneration += 1; pendingSample = nil; enqueueTask?.cancel(); enqueueTask = nil
    receiver.flush()
    let generation = enqueueGeneration
    let seconds = navigationSeconds()
    let first = min(navigationPageCount - 1, max(0, Int(seconds / SnapshotViewportPages.secondsPerPage)))
    let total = navigationPageCount
    enqueueTask = Task { @MainActor [weak self] in
      for index in first..<min(total, first + 2) {
        guard let self, !Task.isCancelled, self.enqueueGeneration == generation else { break }
        let buffer = self.navigationFrames[index]
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer,
          formatDescriptionOut: &description) == noErr, let description else { break }
        let start = index == first ? seconds : Double(index) * SnapshotViewportPages.secondsPerPage
        let end = Double(index + 1) * SnapshotViewportPages.secondsPerPage
        var timing = CMSampleTimingInfo(duration: CMTime(seconds: end - start, preferredTimescale: 600),
          presentationTimeStamp: CMTime(seconds: start, preferredTimescale: 600), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer,
          formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { break }
        do {
          let result = try await self.receiver.enqueue(CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(unsafeBuffer: sample))
          guard !Task.isCancelled, self.enqueueGeneration == generation else { break }
          guard case .enqueued = result else { self.onState?("render_enqueue_failed"); break }
          self.rendered += 1
        } catch { if !Task.isCancelled { self.onState?("render_enqueue_failed") }; break }
      }
      if self?.enqueueGeneration == generation { self?.enqueueTask = nil }
    }
  }


  init(protectCapture: Bool = false, screenAspect: Bool = false, halfScreenLayout: HalfScreenPiPLayout? = nil) {
    self.halfScreenLayout = halfScreenLayout
    super.init()
    if let layout = halfScreenLayout { contentWidth = layout.width; contentHeight = layout.height }
    else if screenAspect { contentWidth = 720; contentHeight = 1280 }
    layer.videoGravity = .resizeAspect
    layer.preventsCapture = protectCapture
    receiver = synchronizer.sampleBufferReceiver(adding: layer.sampleBufferRenderer)
    synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
    synchronizer.setRate(1, time: .zero)
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
    controller = AVPictureInPictureController(contentSource: source)
    controller?.delegate = self
    controller?.requiresLinearPlayback = true
    controller?.canStartPictureInPictureAutomaticallyFromInline = false
    readiness = controller?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, change in
      DispatchQueue.main.async { [weak self] in self?.onReadiness?(change.newValue ?? false) }
    }
  }

  func start() {
    guard let controller else { onState?("pip_unsupported"); return }
    guard controller.isPictureInPicturePossible else { onState?("pip_not_ready"); return }
    controller.startPictureInPicture()
  }

  func enableAutomaticStart() {
    controller?.canStartPictureInPictureAutomaticallyFromInline = true
  }

  var isActive: Bool { controller?.isPictureInPictureActive == true }

  var diagnostics: [String: Any] {
    let seconds = synchronizer.currentTime().seconds
    return ["supported": AVPictureInPictureController.isPictureInPictureSupported(),
            "possible": controller?.isPictureInPicturePossible ?? false,
            "active": controller?.isPictureInPictureActive ?? false,
            "layerReady": layer.isReadyForDisplay, "enqueued": rendered,
            "layerAttached": layer.superlayer != nil, "layerHidden": layer.isHidden,
            "layerWidth": Double(layer.bounds.width), "layerHeight": Double(layer.bounds.height),
            "iosurfaceBacked": lastBufferIOSurface,
            "preventsCapture": layer.preventsCapture,
            "pendingFrames": pendingSample == nil ? 0 : 1, "enqueueInFlight": enqueueTask != nil,
            "videoWidth": contentWidth, "videoHeight": contentHeight,
            "halfScreenMode": halfScreenLayout != nil,
            "detectedPiPPosition": detectedPosition?.rawValue ?? "unknown",
            "automaticPositionConfirmed": detectedPosition != nil,
            "manualPaging": halfScreenLayout == nil,
            "displayedHalf": navigationPage == 1 ? "bottom" : "top",
            "pipRenderWidth": pipRenderSize.width, "pipRenderHeight": pipRenderSize.height,
            "timebaseRate": CMTimebaseGetRate(synchronizer.timebase),
            "timelineSeconds": seconds.isFinite ? seconds : 0,
            "navigationParts": navigationPageCount, "navigationPart": navigationPage,
            "navigationPaused": navigationPaused, "navigationSkips": navigationSkipCount]
  }

  func stop() {
    controller?.canStartPictureInPictureAutomaticallyFromInline = false
    navigationTimer?.invalidate(); navigationTimer = nil; navigationFrames.removeAll(); navigationSource = nil
    enqueueGeneration += 1
    pendingSample = nil
    enqueueTask?.cancel(); enqueueTask = nil
    controller?.stopPictureInPicture()
    badgedInput = nil; badgedOutput = nil
    receiver.flush()
  }

  func render(videoCount: UInt64, background: Bool, displayText: String? = nil) {
    if !navigationFrames.isEmpty {
      navigationTimer?.invalidate(); navigationTimer = nil
      navigationFrames.removeAll(); navigationSource = nil; navigationPaused = false
      enqueueGeneration += 1; enqueueTask?.cancel(); enqueueTask = nil; pendingSample = nil
      receiver.flush(); controller?.requiresLinearPlayback = true
      synchronizer.setRate(1, time: .zero); controller?.invalidatePlaybackState()
    }
    let width = halfScreenLayout?.width ?? contentWidth
    let height = halfScreenLayout?.height ?? contentHeight
    var pixelBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
    guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else { onState?("render_buffer_failed"); return }
    lastBufferIOSurface = CVPixelBufferGetIOSurface(pixelBuffer) != nil
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
      CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
      onState?("render_context_failed"); return
    }
    context.setFillColor(UIColor(red: 0.04, green: 0.1, blue: 0.16, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
    UIGraphicsPushContext(context)
    let text = displayText ?? "PIP PROBE — НЕ ПЕРЕВОД\n视频回调 / Video: \(videoCount)\nКадр / 帧: \(frameNumber)\n\(background ? "Фон / 后台" : "Приложение / 前台")"
    (text as NSString).draw(in: CGRect(x: 40, y: 40, width: max(1, width - 80), height: max(1, height - 80)), withAttributes: [
      .font: UIFont.systemFont(ofSize: displayText == nil ? 48 : 36, weight: .semibold), .foregroundColor: UIColor.white
    ])
    UIGraphicsPopContext()
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    enqueue(pixelBuffer)
  }

  func renderScreen(_ image: CVPixelBuffer, previous: Bool = false, badgeText: String? = nil) {
    guard previous else { badgedInput = nil; badgedOutput = nil; enqueue(image); return }
    let label = badgeText ?? "Предыдущий экран • обновляем"
    if badgedInput !== image || badgeLabel != label {
      badgedInput = image; badgeLabel = label
      badgedOutput = previousScreenBadge(image, label: label)
    }
    if let badgedOutput { enqueue(badgedOutput) }
  }

  private func previousScreenBadge(_ image: CVPixelBuffer, label: String) -> CVPixelBuffer? {
    guard CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_32BGRA else { return nil }
    let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image)
    var result: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
    guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &result) == kCVReturnSuccess,
          let result, CVPixelBufferLockBaseAddress(image, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
    guard CVPixelBufferLockBaseAddress(result, []) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(result, []) }
    guard let source = CVPixelBufferGetBaseAddress(image), let target = CVPixelBufferGetBaseAddress(result) else { return nil }
    for row in 0..<height {
      memcpy(target.advanced(by: row * CVPixelBufferGetBytesPerRow(result)),
        source.advanced(by: row * CVPixelBufferGetBytesPerRow(image)), width * 4)
    }
    guard let context = CGContext(data: target, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(result), space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
    context.setFillColor(UIColor(white: 0.08, alpha: 0.95).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: 76))
    UIGraphicsPushContext(context)
    (label as NSString).draw(in: CGRect(x: 20, y: 20, width: width - 40, height: 56),
      withAttributes: [.font: UIFont.systemFont(ofSize: 25, weight: .semibold), .foregroundColor: UIColor.white])
    UIGraphicsPopContext()
    return result
  }

  /// Drop queued image from an obsolete screen before showing its new state.
  func invalidateScreen() {
    badgedInput = nil; badgedOutput = nil
    // A completed snapshot remains a coherent, visibly previous video until the
    // next snapshot is ready. Its queue is atomically replaced by presentNavigationFrames.
    guard navigationFrames.isEmpty else { return }
    enqueueGeneration += 1
    pendingSample = nil
    enqueueTask?.cancel(); enqueueTask = nil
    receiver.flush()
  }

  private func enqueue(_ pixelBuffer: CVPixelBuffer) {
    contentWidth = CVPixelBufferGetWidth(pixelBuffer)
    contentHeight = CVPixelBufferGetHeight(pixelBuffer)
    lastBufferIOSurface = CVPixelBufferGetIOSurface(pixelBuffer) != nil
    var description: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
      formatDescriptionOut: &description) == noErr, let description else { return }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 4),
      presentationTimeStamp: synchronizer.currentTime(), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
      formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
    pendingSample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(unsafeBuffer: sample)
    frameNumber += 1
    guard enqueueTask == nil else { return }
    let generation = enqueueGeneration
    enqueueTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self, self.enqueueGeneration == generation, let next = self.pendingSample else { break }
        self.pendingSample = nil
        do {
          let result = try await self.receiver.enqueue(next)
          guard !Task.isCancelled else { break }
          guard case .enqueued = result else { self.onState?("render_enqueue_failed"); break }
          self.rendered += 1
        } catch {
          if !Task.isCancelled { self.onState?("render_enqueue_failed") }
          break
        }
      }
      if self?.enqueueGeneration == generation { self?.enqueueTask = nil }
    }
    // This proves enqueue only. Actual display must be observed on the iPhone.
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { onState?("pip_active") }
  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { onClose?() }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    let failure = error as NSError
    onState?("pip_start_failed:\(failure.domain):\(failure.code)")
  }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
    if halfScreenLayout != nil {
      halfScreenPaused = !playing; navigationPaused = !playing
      synchronizer.setRate(playing ? 1 : 0, time: synchronizer.currentTime())
      onNavigationPlaybackChange?(playing)
      pictureInPictureController.invalidatePlaybackState()
      return
    }
    guard !navigationFrames.isEmpty else { if !playing { onClose?() }; return }
    var seconds = navigationSeconds()
    let restart = playing && seconds >= navigationDuration - 0.02
    if restart { seconds = 0 }
    navigationPaused = !playing
    synchronizer.setRate(playing ? 1 : 0, time: CMTime(seconds: seconds, preferredTimescale: 600))
    if restart { queueNavigationFrames(); updateNavigationState(refreshQueue: false) }
    pictureInPictureController.invalidatePlaybackState()
    onNavigationPlaybackChange?(playing)
  }
  func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
    guard halfScreenLayout == nil, !navigationFrames.isEmpty else { return CMTimeRange(start: .zero, duration: .positiveInfinity) }
    _ = navigationSeconds()
    return CMTimeRange(start: .zero, duration: CMTime(seconds: navigationDuration, preferredTimescale: 600))
  }
  func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { if halfScreenLayout != nil { return halfScreenPaused }; if !navigationFrames.isEmpty { _ = navigationSeconds(); return navigationPaused }; return false }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) { pipRenderSize = newRenderSize }
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
    guard halfScreenLayout == nil, !navigationFrames.isEmpty else { completionHandler(); return }
    let interval = skipInterval.seconds
    guard interval.isFinite else { completionHandler(); return }
    guard interval != 0 else { completionHandler(); return }
    let currentPage = Int(navigationSeconds() / SnapshotViewportPages.secondsPerPage)
    let steps = max(1, Int((abs(interval) / SnapshotViewportPages.secondsPerPage).rounded()))
    let nextPage = min(navigationPageCount - 1, max(0, currentPage + (interval > 0 ? steps : -steps)))
    // Seek to the actual frame boundary so a new part gets a full reading interval.
    let target = Double(nextPage) * SnapshotViewportPages.secondsPerPage
    synchronizer.setRate(navigationPaused ? 0 : 1, time: CMTime(seconds: target, preferredTimescale: 600))
    navigationSkipCount += 1
    queueNavigationFrames(); updateNavigationState(refreshQueue: false)
    pictureInPictureController.invalidatePlaybackState()
    completionHandler()
  }
  func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool { true }
  deinit { navigationTimer?.invalidate(); enqueueTask?.cancel() }
}
#endif
