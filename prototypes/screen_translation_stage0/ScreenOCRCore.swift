import Foundation

/// Revision IDs belong to this session instance; a stopped gate never revives.
/// Callers must keep the gate with its session, not compare IDs across sessions.
final class OCRRevisionGate {
  private let lock = NSLock()
  private var revision: UInt64 = 0
  private var stopped = false

  init() {}

  func advance() -> UInt64 {
    lock.lock(); defer { lock.unlock() }
    guard !stopped else { return revision }
    guard revision < UInt64.max else { stopped = true; return revision }
    revision += 1
    return revision
  }

  func isCurrent(_ id: UInt64) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return !stopped && id != 0 && id == revision
  }

  func stop() {
    lock.lock(); defer { lock.unlock() }
    stopped = true
  }
}

/// Normalized coordinates in an already oriented image, origin at top left.
struct OCRBox: Equatable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double

  /// Vision observations are ROI-relative in the checked native runtime.
  /// Map the lower-left ROI into the oriented full image, then flip Y once.
  static func fromVision(x: Double, y: Double, width: Double, height: Double,
                         imageRegion: (x: Double, y: Double, width: Double, height: Double) = (0, 0, 1, 1)) -> OCRBox {
    let h = height.isFinite ? max(0, height) : 0
    let fullX = imageRegion.x + x * imageRegion.width
    let fullY = imageRegion.y + y * imageRegion.height
    let fullH = h * imageRegion.height
    return clipped(x: fullX, y: 1 - fullY - fullH,
                   width: width * imageRegion.width, height: fullH)
  }

  fileprivate static func clipped(x: Double, y: Double, width: Double, height: Double) -> OCRBox {
    func unit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
    let finiteX = x.isFinite ? x : 0
    let finiteY = y.isFinite ? y : 0
    let w = width.isFinite ? max(0, width) : 0
    let h = height.isFinite ? max(0, height) : 0
    let left = unit(finiteX), top = unit(finiteY)
    return OCRBox(x: left, y: top,
                  width: max(0, unit(finiteX + w) - left),
                  height: max(0, unit(finiteY + h) - top))
  }
}

/// EXIF values match CGImagePropertyOrientation without depending on Apple UI APIs.
enum OCROrientation: Int {
  case up = 1, upMirrored, down, downMirrored, leftMirrored, right, rightMirrored, left

  /// Input is a raw-image top-left box; output is in oriented image coordinates.
  /// Vision boxes already produced using an orientation must not be rotated again.
  func orient(_ box: OCRBox) -> OCRBox {
    let b = OCRBox.clipped(x: box.x, y: box.y, width: box.width, height: box.height)
    let points = [(b.x, b.y), (b.x + b.width, b.y),
                  (b.x, b.y + b.height), (b.x + b.width, b.y + b.height)]
    let transformed: [(Double, Double)] = points.map { x, y in
      switch self {
      case .up: return (x, y)
      case .upMirrored: return (1 - x, y)
      case .down: return (1 - x, 1 - y)
      case .downMirrored: return (x, 1 - y)
      case .leftMirrored: return (y, x)
      case .right: return (1 - y, x)
      case .rightMirrored: return (1 - y, 1 - x)
      case .left: return (y, 1 - x)
      }
    }
    let xs = transformed.map(\.0), ys = transformed.map(\.1)
    let left = xs.min()!, top = ys.min()!
    return OCRBox.clipped(x: left, y: top, width: xs.max()! - left, height: ys.max()! - top)
  }
}

struct OCRBlock: Equatable {
  let id: String
  let text: String
  let box: OCRBox
  let confidence: Float
}

enum OCRText {
  /// NFC and whitespace only. Numbers, punctuation, units and negations are data.
  static func normalize(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  /// Initial horizontal-reading policy: top-to-bottom anchored rows, then left-to-right.
  /// Row tolerance is half the smaller line height. The row anchor is immutable;
  /// fuzzy comparisons are never used as a sort comparator or chained across rows.
  /// This is not a paragraph/table/vertical-writing layout reconstruction algorithm.
  static func readingOrder(_ blocks: [OCRBlock]) -> [OCRBlock] {
    func geometry(_ b: OCRBlock) -> OCRBox {
      OCRBox.clipped(x: b.box.x, y: b.box.y, width: b.box.width, height: b.box.height)
    }
    func tie(_ a: OCRBlock, _ b: OCRBlock) -> Bool {
      if a.id != b.id { return a.id < b.id }
      if a.text != b.text { return a.text < b.text }
      return a.confidence.bitPattern < b.confidence.bitPattern
    }
    let sorted = blocks.sorted { a, b in
      let p = geometry(a), q = geometry(b)
      if p.y != q.y { return p.y < q.y }
      if p.x != q.x { return p.x < q.x }
      if p.height != q.height { return p.height < q.height }
      if p.width != q.width { return p.width < q.width }
      return tie(a, b)
    }
    var rows: [[OCRBlock]] = []
    for block in sorted {
      if let anchor = rows.last?.first {
        let a = geometry(anchor), b = geometry(block)
        if b.y - a.y <= 0.5 * min(a.height, b.height) {
          rows[rows.count - 1].append(block)
          continue
        }
      }
      rows.append([block])
    }
    return rows.flatMap { row in
      row.sorted { a, b in
        let p = geometry(a), q = geometry(b)
        if p.x != q.x { return p.x < q.x }
        if p.y != q.y { return p.y < q.y }
        if p.width != q.width { return p.width < q.width }
        if p.height != q.height { return p.height < q.height }
        return tie(a, b)
      }
    }
  }
}

struct ScreenFingerprint: Equatable {
  private let samples: [UInt8]

  init(samples: [UInt8]) { self.samples = samples }

  /// Detects a changed sampled glyph even when global mean difference is small.
  /// The caller still owns sampling/grid alignment; this cannot detect unsampled pixels.
  func hasLocalizedChange(to other: ScreenFingerprint, threshold: Double = 0.08) -> Bool {
    guard samples.count == other.samples.count else { return true }
    let limit = threshold.isFinite ? min(1, max(0, threshold)) : 0.08
    return zip(samples, other.samples).contains {
      Double(abs(Int($0.0) - Int($0.1))) / 255 > limit
    }
  }

  /// Fraction of sampled cells with a visible change; independent of brightness magnitude.
  func changedFraction(to other: ScreenFingerprint, threshold: Double = 0.08) -> Double {
    guard samples.count == other.samples.count else { return 1 }
    guard !samples.isEmpty else { return 0 }
    let limit = threshold.isFinite ? min(1, max(0, threshold)) : 0.08
    let count = zip(samples, other.samples).filter {
      Double(abs(Int($0.0) - Int($0.1))) / 255 > limit
    }.count
    return Double(count) / Double(samples.count)
  }

  /// Bounding rectangle of changed grid cells, in normalized top-left coordinates.
  /// Invalid geometry/counts conservatively invalidate the full screen.
  func changedBounds(to other: ScreenFingerprint, columns: Int, rows: Int,
                     threshold: Double = 0.08) -> OCRBox? {
    let full = OCRBox(x: 0, y: 0, width: 1, height: 1)
    guard columns > 0, rows > 0, columns <= Int.max / rows,
          samples.count == columns * rows, other.samples.count == samples.count else { return full }
    let limit = threshold.isFinite ? min(1, max(0, threshold)) : 0.08
    var minX = columns, minY = rows, maxX = -1, maxY = -1
    for index in samples.indices {
      guard Double(abs(Int(samples[index]) - Int(other.samples[index]))) / 255 > limit else { continue }
      let x = index % columns, y = index / columns
      minX = min(minX, x); minY = min(minY, y)
      maxX = max(maxX, x); maxY = max(maxY, y)
    }
    guard maxX >= 0 else { return nil }
    return OCRBox(x: Double(minX) / Double(columns), y: Double(minY) / Double(rows),
      width: Double(maxX - minX + 1) / Double(columns), height: Double(maxY - minY + 1) / Double(rows))
  }

  /// Mean absolute grayscale-grid difference, normalized to 0...1.
  /// Caller must use the same grid geometry/orientation, not merely equal byte counts.
  func distance(to other: ScreenFingerprint) -> Double {
    guard samples.count == other.samples.count else { return 1 }
    guard !samples.isEmpty else { return 0 }
    let difference = zip(samples, other.samples).reduce(0.0) {
      $0 + Double(abs(Int($1.0) - Int($1.1)))
    }
    return difference / (Double(samples.count) * 255)
  }
}

/// Simple global-frame stability experiment. No banner/tile motion exclusion is claimed.
/// Storage is bounded to one candidate and one last-emitted fingerprint.
struct ScreenStability {
  private let threshold: Double
  private let settleSeconds: TimeInterval
  private let changedAreaThreshold: Double?
  private var candidate: ScreenFingerprint?
  private var emitted: ScreenFingerprint?
  private var stableSince: TimeInterval?
  private var lastTime: TimeInterval?

  init(threshold: Double = 0.025, settleSeconds: Double = 0.4, changedAreaThreshold: Double? = nil) {
    self.changedAreaThreshold = changedAreaThreshold.map { $0.isFinite ? min(1, max(0, $0)) : 0.15 }
    self.threshold = threshold.isFinite ? min(1, max(0, threshold)) : 0.025
    self.settleSeconds = settleSeconds.isFinite ? max(0, settleSeconds) : 0.4
  }

  /// Emits once after a changed candidate settles. Small jitter does not reset its timer.
  /// Returning to an already emitted screen after a brief transient does not emit again.
  mutating func observe(_ fingerprint: ScreenFingerprint, now: TimeInterval) -> Bool {
    guard now.isFinite else { reset(); return false }
    if let lastTime, now < lastTime { reset() }
    lastTime = now
    func differs(_ a: ScreenFingerprint, _ b: ScreenFingerprint) -> Bool {
      if let area = changedAreaThreshold { return a.changedFraction(to: b) >= area }
      return a.distance(to: b) > threshold
    }
    if candidate == nil || differs(candidate!, fingerprint) {
      candidate = fingerprint
      stableSince = now
    }
    guard let candidate, let stableSince, now - stableSince >= settleSeconds else { return false }
    if let emitted, !differs(emitted, candidate) { return false }
    emitted = fingerprint
    self.candidate = fingerprint
    return true
  }

  mutating func reset() {
    candidate = nil
    emitted = nil
    stableSince = nil
    lastTime = nil
  }
}

/// An edge-anchored strip with the same 16:9 aspect as the PiP output.
struct ScreenTranslationViewport {
  let pipAtTop: Bool
  func box(width: Double, height: Double) -> OCRBox {
    guard width.isFinite, height.isFinite, width > 0, height > 0 else {
      return OCRBox(x: 0, y: 0, width: 1, height: 1)
    }
    let fraction = min(1, width * 9 / 16 / height)
    return OCRBox(x: 0, y: pipAtTop ? 1 - fraction : 0, width: 1, height: fraction)
  }
}

/// Full-width strips of an already oriented snapshot; normalized origin is top left.
/// Invalid geometry/configuration or a snapshot requiring more than `cap` pages
/// yields an empty plan rather than silently leaving gaps. At most eight pages.
struct SnapshotViewportPages {
  let boxes: [OCRBox]
  static let secondsPerPage: Double = 15
  var duration: Double { Double(boxes.count) * Self.secondsPerPage }

  init(width: Double, height: Double, aspect: Double = 16.0 / 9.0,
       overlap: Double = 0.2, cap: Int = 8, halfScreen: Bool = false) {
    guard width.isFinite, height.isFinite, width > 0, height > 0,
          aspect.isFinite, aspect > 0, overlap.isFinite, overlap >= 0, overlap < 1,
          cap > 0 else { boxes = []; return }
    if halfScreen {
      guard cap >= 2 else { boxes = []; return }
      boxes = [OCRBox(x: 0, y: 0, width: 1, height: 0.5),
               OCRBox(x: 0, y: 0.5, width: 1, height: 0.5)]
      return
    }
    let stripHeight = min(1, (width / height) / aspect)
    let step = stripHeight * (1 - overlap)
    guard stripHeight > 0, step > 0 else { boxes = []; return }
    let intervals = ceil((1 - stripHeight) / step)
    guard intervals.isFinite, intervals < Double(min(8, cap)) else { boxes = []; return }
    let count = Int(intervals) + 1
    boxes = (0..<count).map { index in
      OCRBox(x: 0, y: min(Double(index) * step, 1 - stripHeight), width: 1, height: stripHeight)
    }
  }

  /// Each strip occupies [index * 15, (index + 1) * 15). Out-of-range times clamp.
  /// Empty plans return nil; NaN is treated as the start of the snapshot.
  func pageIndex(atSeconds seconds: Double) -> Int? {
    guard !boxes.isEmpty else { return nil }
    let time = clampedTime(seconds)
    return min(boxes.count - 1, Int(time / Self.secondsPerPage))
  }

  /// Relative seek for PiP controls, clamped to [0, duration - 0.000001].
  /// An invalid interval is ignored. Empty plans always return zero.
  func clampedSkip(current: Double, interval: Double) -> Double {
    let start = clampedTime(current)
    return clampedTime(start + (interval.isNaN ? 0 : interval))
  }

  private func clampedTime(_ seconds: Double) -> Double {
    guard duration > 0 else { return 0 }
    if seconds.isNaN { return 0 }
    return min(duration - 0.000001, max(0, seconds))
  }
}

/// Buffer geometry for one half of a physical screen. This does not prescribe
/// the system PiP window size. Even output height supports the video renderer.
struct HalfScreenPiPLayout {
  let width: Int
  let height: Int
  let captureWidth: Int
  let captureHeight: Int

  init?(screenWidth: Double, screenHeight: Double, safeAreaTop: Double = 0, safeAreaBottom: Double = 0) {
    guard screenWidth.isFinite, screenHeight.isFinite,
          screenWidth > 0, screenHeight > 0,
          screenWidth <= 8192, screenHeight <= 8192,
          screenWidth * screenHeight <= 16_777_216 else { return nil }
    guard safeAreaTop.isFinite, safeAreaBottom.isFinite, safeAreaTop >= 0, safeAreaBottom >= 0,
          safeAreaTop + safeAreaBottom < screenHeight else { return nil }
    let usableHeight = screenHeight - safeAreaTop - safeAreaBottom
    let outputWidth = 960
    let requestedHeight = Double(outputWidth) * usableHeight / (2 * screenWidth)
    guard requestedHeight.isFinite, requestedHeight > 0 else { return nil }
    let evenHeight = (requestedHeight / 2).rounded() * 2
    guard evenHeight >= 2, evenHeight <= 8192,
          Double(outputWidth) * evenHeight <= 16_777_216 else { return nil }
    let sourceWidth = 720
    let requestedCaptureHeight = Double(sourceWidth) * screenHeight / screenWidth
    guard requestedCaptureHeight.isFinite, requestedCaptureHeight > 0 else { return nil }
    let evenCaptureHeight = (requestedCaptureHeight / 2).rounded() * 2
    guard evenCaptureHeight >= 2, evenCaptureHeight <= 8192,
          Double(sourceWidth) * evenCaptureHeight <= 16_777_216 else { return nil }
    width = outputWidth
    height = Int(evenHeight)
    captureWidth = sourceWidth
    captureHeight = Int(evenCaptureHeight)
  }
}

/// Position inferred from a protected dark PiP mask, never from a public window
/// coordinate. A naturally identical rounded black card is indistinguishable.
enum PiPVerticalPosition: String { case top, bottom }

/// Full-width source region opposite the confirmed protected PiP rectangle.
/// The actual window may cross the 50% line; leave a 2%-of-screen guard band
/// rather than showing any protected pixels at the edge of the translation.
enum PiPVisibleRegion {
  static func box(position: PiPVerticalPosition, mask: OCRBox?) -> OCRBox? {
    guard let mask, mask.x.isFinite, mask.y.isFinite, mask.width.isFinite, mask.height.isFinite,
          mask.x >= 0, mask.y >= 0, mask.width > 0, mask.height > 0,
          mask.x + mask.width <= 1, mask.y + mask.height <= 1 else { return nil }
    switch position {
    case .bottom:
      let end = min(0.5, mask.y - 0.02)
      guard end > 0 else { return nil }
      return OCRBox(x: 0, y: 0, width: 1, height: end)
    case .top:
      let start = max(0.5, mask.y + mask.height + 0.02)
      guard start < 1 else { return nil }
      return OCRBox(x: 0, y: start, width: 1, height: 1 - start)
    }
  }
}

struct PiPPositionDetector {
  private struct Candidate {
    let side: PiPVerticalPosition
    let x: Double, y: Double, width: Double, height: Double
  }
  private var gridWidth = 0
  private var gridHeight = 0
  private var sourceOrientation: UInt32?
  private var confirmed: PiPVerticalPosition?
  private(set) var confirmedMask: OCRBox?
  private var pending: Candidate?
  private var pendingSince: TimeInterval = 0
  private var observations = 0
  private var lastTime: TimeInterval?
  private var componentDiagnostics: [[String: Any]] = []
  private var candidateCount = 0
  private var observationGap: TimeInterval = 0
  private var topBlackFraction = 0.0, bottomBlackFraction = 0.0
  private var solidRectangles: [[String: Any]] = []

  /// Bounded geometry/counters only: no frame pixels or recognized content.
  var diagnostics: [String: Any] {
    ["confirmed": confirmed?.rawValue ?? "unknown", "pendingCount": observations,
     "candidateCount": candidateCount, "observationGapMs": observationGap * 1000,
     "components": componentDiagnostics, "solidRectangles": solidRectangles,
     "topBlackFraction": topBlackFraction, "bottomBlackFraction": bottomBlackFraction]
  }

  /// Sampler owns orientation; equal-size flips must reset just like rotations.
  mutating func prepareOrientation(_ rawValue: UInt32) {
    if let old = sourceOrientation, old != rawValue { resetTracking() }
    sourceOrientation = rawValue
  }

  private mutating func resetTracking() {
    confirmed = nil; confirmedMask = nil; pending = nil; observations = 0; lastTime = nil
  }

  mutating func observe(width: Int, height: Int, luma: [UInt8], expectedAspect: Double,
                        now: TimeInterval) -> PiPVerticalPosition? {
    guard width > 0, height > 0, width <= 512, height <= 512,
          width <= 80_000 / height, luma.count == width * height,
          expectedAspect.isFinite, expectedAspect > 0, now.isFinite else {
      pending = nil; observations = 0
      return confirmed
    }
    if gridWidth != width || gridHeight != height {
      resetTracking(); gridWidth = width; gridHeight = height
    }
    observationGap = lastTime.map { max(0, now - $0) } ?? 0
    if let lastTime, now < lastTime || now - lastTime > 3 { pending = nil; observations = 0 }
    lastTime = now
    let middle = width * (height / 2)
    topBlackFraction = Double(luma[..<middle].filter { $0 <= 12 }.count) / Double(max(1, middle))
    bottomBlackFraction = Double(luma[middle...].filter { $0 <= 12 }.count) / Double(max(1, luma.count - middle))
    let detection = Self.candidates(width: width, height: height, luma: luma, aspect: expectedAspect)
    let candidates = detection.candidates
    componentDiagnostics = detection.diagnostics
    candidateCount = candidates.count
    solidRectangles = candidates.prefix(4).map { ["side": $0.side.rawValue, "x": $0.x, "y": $0.y,
      "width": $0.width, "height": $0.height] }
    guard candidates.count == 1, let candidate = candidates.first else {
      pending = nil; observations = 0
      return confirmed
    }
    let continuous = pending.map { previous in
      previous.side == candidate.side && abs(previous.x - candidate.x) <= 0.035 &&
        abs(previous.y - candidate.y) <= 0.035 &&
        abs(previous.width - candidate.width) <= 0.04 && abs(previous.height - candidate.height) <= 0.04
    } ?? false
    if continuous { observations += 1 }
    else { pendingSince = now; observations = 1 }
    pending = candidate
    if observations >= 3 && now - pendingSince >= 0.5 {
      confirmed = candidate.side
      confirmedMask = OCRBox(x: candidate.x, y: candidate.y, width: candidate.width, height: candidate.height)
    }
    return confirmed
  }

  private static func candidates(width: Int, height: Int, luma: [UInt8], aspect: Double)
    -> (candidates: [Candidate], diagnostics: [[String: Any]]) {
    let black: UInt8 = 12
    var visited = [Bool](repeating: false, count: luma.count)
    var queue: [Int] = []
    var result: [Candidate] = []
    var reports: [(area: Int, data: [String: Any])] = []
    func evaluate(left: Int, right: Int, top: Int, bottom: Int, darkCount: Int) {
      let w = right - left + 1, h = bottom - top + 1
      let wf = Double(w) / Double(width), hf = Double(h) / Double(height)
      let fill = Double(darkCount) / Double(w * h)
      // Ignore glyph-sized components in metadata as well as in detection.
      guard wf >= 0.15, hf >= 0.08 else { return }
      var report: [String: Any] = ["x": Double(left) / Double(width), "y": Double(top) / Double(height),
        "width": wf, "height": hf, "fill": fill, "aspect": Double(w) / Double(h)]
      func reject(_ reason: String) {
        report["reason"] = reason; reports.append((w * h, report))
      }
      guard w >= 8, h >= 8, wf >= 0.2, hf >= 0.1, hf <= 0.65 else { reject("size"); return }
      // A full-width mask may reach the display edge. A narrow clipped/stashed
      // window cannot be reconstructed reliably and remains ambiguous.
      let touchesEdge = left == 0 || top == 0 || right + 1 == width || bottom + 1 == height
      guard !touchesEdge || wf >= 0.9 else { reject("clipped"); return }
      guard Double(min(left, width - right - 1)) / Double(width) <= 0.12,
            Double(min(top, height - bottom - 1)) / Double(height) <= 0.12 else { reject("edge"); return }
      guard abs(Double(w) / Double(h) / aspect - 1) <= 0.25 else { reject("aspect"); return }
      guard fill >= 0.9 else { reject("fill"); return }
      let center = Double(top + bottom + 1) / (2 * Double(height))
      let side: PiPVerticalPosition
      if center < 0.45 { side = .top } else if center > 0.55 { side = .bottom }
      else { reject("middle"); return }
      // Capture protection can produce square corners even for rounded PiP.
      // Verify a solid interior; do not require bright corner pixels.
      let insetX = max(1, w / 5), insetY = max(1, h / 5)
      var inner = 0, innerBlack = 0, innerTotal = 0
      for y in (top + insetY)...(bottom - insetY) {
        for x in (left + insetX)...(right - insetX) {
          inner += 1; innerTotal += Int(luma[y * width + x])
          if luma[y * width + x] <= black { innerBlack += 1 }
        }
      }
      report["innerBlackFraction"] = Double(innerBlack) / Double(inner)
      guard Double(innerBlack) / Double(inner) >= 0.98 else { reject("interior"); return }
      // A band tolerates antialiasing/shadow and surrounding dark UI. The
      // comparison is relative to the protected interior, not a white theme.
      let band = max(2, min(w, h) / 16)
      let innerMean = Double(innerTotal) / Double(inner)
      var outsideCount = 0, outsideTotal = 0, contrastCount = 0
      for y in max(0, top - band)...min(height - 1, bottom + band) {
        for x in max(0, left - band)...min(width - 1, right + band) {
          if x >= left && x <= right && y >= top && y <= bottom { continue }
          let value = Int(luma[y * width + x])
          outsideCount += 1; outsideTotal += value
          if Double(value) >= max(20, innerMean + 12) { contrastCount += 1 }
        }
      }
      let outsideMean = outsideCount > 0 ? Double(outsideTotal) / Double(outsideCount) : 0
      let contrast = outsideCount > 0 ? Double(contrastCount) / Double(outsideCount) : 0
      report["outsideMean"] = outsideMean; report["contrastFraction"] = contrast
      guard outsideCount > 0, outsideMean - innerMean >= 12, contrast >= 0.45 else { reject("contrast"); return }
      report["reason"] = "accepted"; reports.append((w * h, report))
      let candidate = Candidate(side: side, x: Double(left) / Double(width), y: Double(top) / Double(height), width: wf, height: hf)
      // Histogram rectangles may differ slightly inside one rounded mask. Merge
      // overlapping candidates for that same window, never distinct top/bottom.
      if !result.contains(where: { existing in
        guard existing.side == candidate.side else { return false }
        let overlapW = max(0, min(existing.x + existing.width, candidate.x + candidate.width) - max(existing.x, candidate.x))
        let overlapH = max(0, min(existing.y + existing.height, candidate.y + candidate.height) - max(existing.y, candidate.y))
        let intersection = overlapW * overlapH
        return intersection / min(existing.width * existing.height, candidate.width * candidate.height) >= 0.7
      }) { result.append(candidate) }
    }
    for start in luma.indices where !visited[start] && luma[start] <= black {
      queue.removeAll(keepingCapacity: true); queue.append(start); visited[start] = true
      var cursor = 0, left = start % width, right = left, top = start / width, bottom = top
      func visit(_ index: Int) {
        if !visited[index] && luma[index] <= black { visited[index] = true; queue.append(index) }
      }
      while cursor < queue.count {
        let index = queue[cursor], x = index % width, y = index / width
        cursor += 1
        left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
        if x > 0 { visit(index - 1) }; if x + 1 < width { visit(index + 1) }
        if y > 0 { visit(index - width) }; if y + 1 < height { visit(index + width) }
      }
      evaluate(left: left, right: right, top: top, bottom: bottom, darkCount: queue.count)
    }
    // A protected mask can touch black page artwork. Its connected component
    // then has the wrong bounding aspect/fill. Extract maximal solid interiors
    // with a bounded O(width*height) histogram instead of using that merged box.
    var heights = [Int](repeating: 0, count: width)
    for y in 0..<height {
      for x in 0..<width { heights[x] = luma[y * width + x] <= black ? heights[x] + 1 : 0 }
      var stack: [(start: Int, height: Int)] = []
      for x in 0...width {
        let current = x < width ? heights[x] : 0
        var start = x
        while let last = stack.last, last.height > current {
          _ = stack.popLast(); start = last.start
          let w = x - last.start, h = last.height
          guard w >= 8, h >= 8, Double(w) / Double(width) >= 0.2,
                Double(h) / Double(height) >= 0.1,
                abs(Double(w) / Double(h) / aspect - 1) <= 0.25 else { continue }
          // Only vertically maximal rectangles: partial rows inside a whole
          // black screen must not invent PiP-sized candidate windows.
          if y + 1 < height && (last.start..<x).allSatisfy({ luma[(y + 1) * width + $0] <= black }) { continue }
          evaluate(left: last.start, right: x - 1, top: y - h + 1, bottom: y, darkCount: w * h)
        }
        if current > 0 && (stack.last?.height ?? 0) < current { stack.append((start, current)) }
      }
    }
    return (result, reports.sorted { $0.area > $1.area }.prefix(4).map { $0.data })
  }
}
