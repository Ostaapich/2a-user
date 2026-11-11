import Foundation

@main
struct ScreenOCRCoreTests {
  static func main() {
    let revisions = OCRRevisionGate()
    precondition(!revisions.isCurrent(0))
    let frameA = revisions.advance()
    precondition(revisions.isCurrent(frameA))
    let frameB = revisions.advance()
    precondition(frameB > frameA && !revisions.isCurrent(frameA) && revisions.isCurrent(frameB))
    DispatchQueue.concurrentPerform(iterations: 1000) { _ in precondition(!revisions.isCurrent(frameA)) }
    revisions.stop()
    let afterStop = revisions.advance()
    precondition(!revisions.isCurrent(frameB) && !revisions.isCurrent(afterStop))
    let newSession = OCRRevisionGate()
    let newFrame = newSession.advance()
    precondition(newSession.isCurrent(newFrame))
    // Different sessions may reuse the same numeric revision; owner identity matters.
    precondition(!revisions.isCurrent(newFrame))
    DispatchQueue.concurrentPerform(iterations: 1000) { _ in precondition(!revisions.isCurrent(frameB)) }
    func near(_ actual: Double, _ expected: Double) { precondition(abs(actual - expected) < 0.000_001, "\(actual) != \(expected)") }
    func box(_ actual: OCRBox, _ expected: [Double]) {
      for (a, b) in zip([actual.x, actual.y, actual.width, actual.height], expected) { near(a, b) }
    }
    for (width, height) in [(720.0, 1280.0), (390.0, 844.0), (430.0, 932.0),
                            (97.0, 161.0), (161.0, 97.0), (1280.0, 720.0)] {
      let halves = SnapshotViewportPages(width: width, height: height, halfScreen: true)
      precondition(halves.boxes.count == 2)
      box(halves.boxes[0], [0, 0, 1, 0.5]); box(halves.boxes[1], [0, 0.5, 1, 0.5])
      near(halves.duration, 30)
      precondition(halves.pageIndex(atSeconds: 14.999) == 0 && halves.pageIndex(atSeconds: 15) == 1)
      precondition(halves.pageIndex(atSeconds: 30) == 1)
    }
    for invalid in [SnapshotViewportPages(width: 0, height: 1280, halfScreen: true),
                    SnapshotViewportPages(width: 720, height: -.infinity, halfScreen: true),
                    SnapshotViewportPages(width: .nan, height: 1280, halfScreen: true),
                    SnapshotViewportPages(width: 720, height: 1280, cap: 1, halfScreen: true)] {
      precondition(invalid.boxes.isEmpty)
    }
    for (width, height, expectedHeight, expectedCaptureHeight) in [(390.0, 844.0, 1038, 1558), (430.0, 932.0, 1040, 1560),
                                           (844.0, 390.0, 222, 332), (720.0, 1280.0, 854, 1280)] {
      let layout = HalfScreenPiPLayout(screenWidth: width, screenHeight: height)!
      precondition(layout.width == 960 && layout.height == expectedHeight && layout.height % 2 == 0)
      precondition(abs(Double(layout.height) - 960 * height / (2 * width)) <= 1)
      precondition(layout.captureWidth == 720 && layout.captureHeight == expectedCaptureHeight && layout.captureHeight % 2 == 0)
      precondition(abs(Double(layout.captureHeight) - 720 * height / width) <= 1)
    }
    for (width, height) in [(0.0, 844.0), (-1.0, 844.0), (Double.nan, 844.0),
                            (390.0, Double.infinity), (9000.0, 844.0), (8192.0, 8192.0),
                            (1.0, 8192.0), (8192.0, 1.0), (Double.leastNonzeroMagnitude, 844.0),
                            (500.0, 6000.0)] {
      precondition(HalfScreenPiPLayout(screenWidth: width, screenHeight: height) == nil)
    }
    let safeLayout = HalfScreenPiPLayout(screenWidth: 440, screenHeight: 956, safeAreaTop: 62, safeAreaBottom: 34)!
    let fullLayout = HalfScreenPiPLayout(screenWidth: 440, screenHeight: 956)!
    precondition(safeLayout.height == 938 && safeLayout.height < fullLayout.height)
    precondition(safeLayout.captureHeight == fullLayout.captureHeight, "Safe areas only affect PiP output, never source capture")
    for inset in [-1.0, Double.nan, Double.infinity, 956.0] {
      precondition(HalfScreenPiPLayout(screenWidth: 440, screenHeight: 956, safeAreaTop: inset) == nil)
    }
    func mask(top: Bool, second: Bool = false, rounded: Bool = true, background: UInt8 = 200, stash: Bool = false) -> [UInt8] {
      let width = 96, height = 208
      var pixels = [UInt8](repeating: background, count: width * height)
      func draw(y originY: Int) {
        let left = stash ? -20 : 8, right = left + 78, bottom = originY + 84
        for y in max(0, originY)..<min(height, bottom) { for x in max(0, left)..<min(width, right) {
          let dx = max(0, max(Double(left + 10) - Double(x) - 0.5, Double(x) + 0.5 - Double(right - 10)))
          let dy = max(0, max(Double(originY + 10) - Double(y) - 0.5, Double(y) + 0.5 - Double(bottom - 10)))
          if !rounded || dx * dx + dy * dy <= 100 { pixels[y * width + x] = 0 }
        } }
      }
      draw(y: top ? 8 : 116); if second { draw(y: top ? 116 : 8) }
      return pixels
    }
    let upperMask = OCRBox(x: 0.02, y: 0.08, width: 0.96, height: 0.48)
    let lowerMask = OCRBox(x: 0.02, y: 0.45, width: 0.96, height: 0.48)
    box(PiPVisibleRegion.box(position: .top, mask: upperMask)!, [0, 0.58, 1, 0.42])
    box(PiPVisibleRegion.box(position: .bottom, mask: lowerMask)!, [0, 0, 1, 0.43])
    box(PiPVisibleRegion.box(position: .top, mask: OCRBox(x: 0, y: 0.02, width: 1, height: 0.4))!, [0, 0.5, 1, 0.5])
    box(PiPVisibleRegion.box(position: .bottom, mask: OCRBox(x: 0, y: 0.6, width: 1, height: 0.4))!, [0, 0, 1, 0.5])
    for invalid in [nil, OCRBox(x: .nan, y: 0, width: 1, height: 0.4),
      OCRBox(x: 0, y: -.infinity, width: 1, height: 0.4),
      OCRBox(x: 0, y: 0, width: 0, height: 0.4),
      OCRBox(x: -0.1, y: 0, width: 1, height: 0.4),
      OCRBox(x: 0, y: 0.7, width: 1, height: 0.4)] {
      for position in [PiPVerticalPosition.top, .bottom] {
        precondition(PiPVisibleRegion.box(position: position, mask: invalid) == nil)
      }
    }
    precondition(PiPVisibleRegion.box(position: .bottom, mask: OCRBox(x: 0, y: 0.01, width: 1, height: 0.6)) == nil)
    precondition(PiPVisibleRegion.box(position: .top, mask: OCRBox(x: 0, y: 0.4, width: 1, height: 0.59)) == nil)
    var detector = PiPPositionDetector()
    func detect(_ pixels: [UInt8], _ time: Double) -> PiPVerticalPosition? {
      detector.observe(width: 96, height: 208, luma: pixels, expectedAspect: 78.0 / 84, now: time)
    }
    precondition(detect(mask(top: true), 0) == nil)
    precondition(detect(mask(top: true), 0.25) == nil)
    precondition(detect(mask(top: true), 0.49) == nil)
    precondition(detect(mask(top: true), 0.5) == .top)
    precondition(detector.confirmedMask != nil)
    precondition(PiPVisibleRegion.box(position: .top, mask: detector.confirmedMask) != nil)
    precondition(detect(mask(top: false), 0.75) == .top)
    precondition(detect(mask(top: false), 1) == .top)
    precondition(detect(mask(top: false), 1.25) == .bottom)
    for (offset, ambiguous) in [mask(top: true, second: true),
      mask(top: true, background: 8), mask(top: true, stash: true),
      [UInt8](repeating: 0, count: 96 * 208), [UInt8](repeating: 200, count: 96 * 208)].enumerated() {
      precondition(detect(ambiguous, 1.5 + Double(offset) * 0.25) == .bottom)
      var uncertain = PiPPositionDetector()
      for time in [0.0, 0.25, 0.5, 0.75] {
        precondition(uncertain.observe(width: 96, height: 208, luma: ambiguous, expectedAspect: 78.0 / 84, now: time) == nil)
      }
    }
    // Protected video need not preserve PiP's visual corner radius or light UI.
    for top in [true, false] {
      for background: UInt8 in [20, 40, 200] {
        var rectangular = PiPPositionDetector()
        let pixels = mask(top: top, rounded: false, background: background)
        for time in [0.0, 0.25] {
          precondition(rectangular.observe(width: 96, height: 208, luma: pixels,
            expectedAspect: 78.0 / 84, now: time) == nil)
        }
        precondition(rectangular.observe(width: 96, height: 208, luma: pixels,
          expectedAspect: 78.0 / 84, now: 0.5) == (top ? .top : .bottom))
        precondition(rectangular.diagnostics["candidateCount"] as? Int == 1)
        let components = rectangular.diagnostics["components"] as! [[String: Any]]
        precondition(!components.isEmpty && components.count <= 4 && components.contains { $0["reason"] as? String == "accepted" })
      }
    }
    // A grey shadow/antialias band would fail a one-pixel bright ring test.
    var shadow = mask(top: true, rounded: false, background: 80)
    for y in 7...92 { for x in 7...86 {
      if x == 7 || x == 86 || y == 7 || y == 92 { shadow[y * 96 + x] = 16 }
    } }
    var shadowDetector = PiPPositionDetector()
    for time in [0.0, 0.25, 0.5] {
      let result = shadowDetector.observe(width: 96, height: 208, luma: shadow,
        expectedAspect: 78.0 / 84, now: time)
      precondition(result == (time == 0.5 ? .top : nil))
    }
    // Near/full-width masks at the edge remain detectable; stashed small masks do not.
    var edgeMask = [UInt8](repeating: 100, count: 96 * 208)
    for y in 8..<112 { for x in 0..<96 { edgeMask[y * 96 + x] = 0 } }
    var edgeDetector = PiPPositionDetector()
    for time in [0.0, 0.25, 0.5] {
      let result = edgeDetector.observe(width: 96, height: 208, luma: edgeMask,
        expectedAspect: 96.0 / 104, now: time)
      precondition(result == (time == 0.5 ? .top : nil))
    }
    // On-device failure: a bottom PiP mask joins dark artwork above. Component
    // bbox is ~95% wide,59% tall with aspect.74/fill.71; solid interior is PiP.
    func joinedMask(top: Bool) -> [UInt8] {
      var pixels = [UInt8](repeating: 100, count: 96 * 208)
      let y0 = top ? 18 : 100
      for y in y0..<(y0 + 90) { for x in 2..<94 { pixels[y * 96 + x] = 0 } }
      let stem = top ? 108..<142 : 66..<100
      for y in stem { for x in 38..<58 { pixels[y * 96 + x] = 0 } }
      return pixels
    }
    var joined = PiPPositionDetector()
    for time in [0.0, 0.9, 1.8] {
      let value = joined.observe(width: 96, height: 208, luma: joinedMask(top: true), expectedAspect: 92.0 / 90, now: time)
      precondition(value == (time == 1.8 ? .top : nil))
    }
    for time in [2.7, 3.6, 4.5] {
      let value = joined.observe(width: 96, height: 208, luma: joinedMask(top: false), expectedAspect: 92.0 / 90, now: time)
      precondition(value == (time == 4.5 ? .bottom : .top), "Joined lower mask must replace stale top position")
    }
    precondition(joined.diagnostics["candidateCount"] as? Int == 1)
    precondition((joined.diagnostics["solidRectangles"] as! [[String: Any]]).first?["side"] as? String == "bottom")
    precondition((joined.diagnostics["bottomBlackFraction"] as! Double) > (joined.diagnostics["topBlackFraction"] as! Double))
    // A circle/irregular dark patch must not qualify as a dense rounded rectangle.
    var irregular = mask(top: true)
    for y in 40..<90 { for x in 45..<86 { irregular[y * 96 + x] = 200 } }
    var irregularDetector = PiPPositionDetector()
    for time in [0.0, 0.25, 0.5] {
      precondition(irregularDetector.observe(width: 96, height: 208, luma: irregular, expectedAspect: 78.0 / 84, now: time) == nil)
    }
    precondition(detector.observe(width: 192, height: 416, luma: [UInt8](repeating: 200, count: 192 * 416), expectedAspect: 78.0 / 84, now: 4) == nil)
    precondition(detector.confirmedMask == nil)
    var timing = PiPPositionDetector()
    for time in [0.0, 4.0, 8.0] {
      precondition(timing.observe(width: 96, height: 208, luma: mask(top: true), expectedAspect: 78.0 / 84, now: time) == nil)
    }
    precondition(timing.observe(width: 96, height: 208, luma: mask(top: true), expectedAspect: 78.0 / 84, now: 8.25) == nil)
    precondition(timing.observe(width: 96, height: 208, luma: mask(top: true), expectedAspect: 78.0 / 84, now: 8.5) == .top)
    timing.prepareOrientation(1); timing.prepareOrientation(3)
    precondition(timing.confirmedMask == nil)
    precondition(timing.observe(width: 96, height: 208, luma: mask(top: true), expectedAspect: 78.0 / 84, now: 8.75) == nil)
    let pages = SnapshotViewportPages(width: 720, height: 1280)
    precondition(pages.boxes.count == 4)
    near(pages.boxes[0].height * 1280, 405)
    near(pages.boxes[0].y, 0)
    near(pages.boxes.last!.y + pages.boxes.last!.height, 1)
    for (previous, next) in zip(pages.boxes, pages.boxes.dropFirst()) {
      precondition(next.y > previous.y && next.y <= previous.y + previous.height)
      precondition(previous.y + previous.height - next.y >= previous.height * 0.2 - 0.000001)
      near(next.x, 0); near(next.width, 1)
    }
    near(pages.duration, 60)
    for (time, index) in [(0.0, 0), (14.999, 0), (15, 1), (30, 2), (45, 3), (60, 3), (-15, 0)] {
      precondition(pages.pageIndex(atSeconds: time) == index)
    }
    precondition(pages.pageIndex(atSeconds: .nan) == 0)
    precondition(pages.pageIndex(atSeconds: .infinity) == 3)
    precondition(pages.pageIndex(atSeconds: -.infinity) == 0)
    near(pages.clampedSkip(current: 10, interval: 15), 25)
    near(pages.clampedSkip(current: 25, interval: -15), 10)
    near(pages.clampedSkip(current: 10, interval: -100), 0)
    precondition(pages.clampedSkip(current: 50, interval: 15) < pages.duration)
    precondition(pages.pageIndex(atSeconds: pages.clampedSkip(current: 50, interval: 15)) == 3)
    near(pages.clampedSkip(current: .nan, interval: 15), 15)
    near(pages.clampedSkip(current: 10, interval: .nan), 10)
    precondition(pages.clampedSkip(current: 10, interval: .infinity) < pages.duration)
    near(pages.clampedSkip(current: 10, interval: -.infinity), 0)
    for plan in [SnapshotViewportPages(width: 1280, height: 720), SnapshotViewportPages(width: 1920, height: 720)] {
      precondition(plan.boxes == [OCRBox(x: 0, y: 0, width: 1, height: 1)])
      near(plan.duration, 15)
    }
    for plan in [SnapshotViewportPages(width: 0, height: 1280), SnapshotViewportPages(width: -720, height: 1280),
                 SnapshotViewportPages(width: .nan, height: 1280), SnapshotViewportPages(width: 720, height: .infinity),
                 SnapshotViewportPages(width: 720, height: 1280, aspect: 0),
                 SnapshotViewportPages(width: 720, height: 1280, overlap: 1),
                 SnapshotViewportPages(width: 720, height: 1280, cap: 0),
                 SnapshotViewportPages(width: 720, height: 1280, cap: 3),
                 SnapshotViewportPages(width: 1, height: 1000000, cap: 100)] {
      precondition(plan.boxes.isEmpty && plan.duration == 0)
      precondition(plan.pageIndex(atSeconds: 0) == nil)
      near(plan.clampedSkip(current: 10, interval: 15), 0)
    }
    box(OCRBox.fromVision(x: 0.1, y: 0.2, width: 0.3, height: 0.1), [0.1, 0.7, 0.3, 0.1])
    box(OCRBox.fromVision(x: -0.1, y: 0.8, width: 0.4, height: 0.4), [0, 0, 0.3, 0.2])
    box(OCRBox.fromVision(x: 0.9, y: -0.2, width: 0.4, height: 0.4), [0.9, 0.8, 0.1, 0.2])
    box(OCRBox.fromVision(x: 0.2, y: 0.25, width: 0.5, height: 0.2,
      imageRegion: (x: 0.1, y: 0.5, width: 0.8, height: 0.4)), [0.26, 0.32, 0.4, 0.08])
    // Native Vision TOPROW fixture: upper-half ROI maps back to full-image bbox.
    box(OCRBox.fromVision(x: 0.095, y: 0.4866666666666667, width: 0.3325, height: 0.1666666666666667,
      imageRegion: (x: 0, y: 0.5, width: 1, height: 0.5)), [0.095, 0.1733333333333333, 0.3325, 0.0833333333333333])
    let source = OCRBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    let expected: [[Double]] = [
      [0.1, 0.2, 0.3, 0.4], [0.6, 0.2, 0.3, 0.4],
      [0.6, 0.4, 0.3, 0.4], [0.1, 0.4, 0.3, 0.4],
      [0.2, 0.1, 0.4, 0.3], [0.4, 0.1, 0.4, 0.3],
      [0.4, 0.6, 0.4, 0.3], [0.2, 0.6, 0.4, 0.3]]
    let corners = [OCRBox(x: 0, y: 0, width: 0.1, height: 0.2),
                   OCRBox(x: 0.9, y: 0, width: 0.1, height: 0.2),
                   OCRBox(x: 0, y: 0.8, width: 0.1, height: 0.2),
                   OCRBox(x: 0.9, y: 0.8, width: 0.1, height: 0.2)]
    let positions: [[[Double]]] = [
      [[0, 0], [0.9, 0], [0, 0.8], [0.9, 0.8]],
      [[0.9, 0], [0, 0], [0.9, 0.8], [0, 0.8]],
      [[0.9, 0.8], [0, 0.8], [0.9, 0], [0, 0]],
      [[0, 0.8], [0.9, 0.8], [0, 0], [0.9, 0]],
      [[0, 0], [0, 0.9], [0.8, 0], [0.8, 0.9]],
      [[0.8, 0], [0.8, 0.9], [0, 0], [0, 0.9]],
      [[0.8, 0.9], [0.8, 0], [0, 0.9], [0, 0]],
      [[0, 0.9], [0, 0], [0.8, 0.9], [0.8, 0]]]
    for value in 1...8 {
      let orientation = OCROrientation(rawValue: value)!
      precondition(orientation.rawValue == value)
      box(orientation.orient(source), expected[value - 1])
      for (index, corner) in corners.enumerated() {
        let size: [Double] = value < 5 ? [0.1, 0.2] : [0.2, 0.1]
        box(orientation.orient(corner), positions[value - 1][index] + size)
      }
    }
    precondition(OCRText.normalize("\n 不含电池\t 尺寸：30 × 20 cm　¥１２３.50 \r\n 不是纯棉 ") == "不含电池 尺寸：30 × 20 cm ¥１２３.50 不是纯棉")
    precondition(OCRText.normalize("Cafe\u{301}\u{00a0}  2\u{202f}kg") == "Café 2 kg")
    precondition(OCRText.normalize("\t\n　") == "")
    func block(_ id: String, _ x: Double, _ y: Double) -> OCRBlock {
      OCRBlock(id: id, text: id, box: OCRBox(x: x, y: y, width: 0.1, height: 0.04), confidence: 0.9)
    }
    let layout = [block("right-price", 0.6, 0.1), block("left-label", 0.1, 0.105),
                  block("next-row", 0.05, 0.16), block("below", 0.1, 0.3)]
    let order = ["left-label", "right-price", "next-row", "below"]
    precondition(OCRText.readingOrder(layout).map(\.id) == order)
    precondition(OCRText.readingOrder(Array(layout.reversed())).map(\.id) == order)
    let chain = [block("A", 0.7, 0.10), block("B", 0.3, 0.115), block("C", 0.1, 0.13)]
    precondition(OCRText.readingOrder(chain).map(\.id) == ["B", "A", "C"])
    for input in [chain, Array(chain.reversed()), [chain[1], chain[2], chain[0]]] {
      precondition(OCRText.readingOrder(input).map(\.id) == ["B", "A", "C"])
    }
    precondition(OCRText.readingOrder([]).isEmpty)
    func fingerprint(_ value: UInt8) -> ScreenFingerprint { ScreenFingerprint(samples: [UInt8](repeating: value, count: 16)) }
    near(fingerprint(0).distance(to: fingerprint(255)), 1)
    near(fingerprint(40).distance(to: fingerprint(45)), 5 / 255)
    near(ScreenFingerprint(samples: [0, 255]).distance(to: ScreenFingerprint(samples: [255, 255])), 0.5)
    precondition(fingerprint(0).distance(to: ScreenFingerprint(samples: [0])) == 1)
    precondition(ScreenFingerprint(samples: []).distance(to: ScreenFingerprint(samples: [])) == 0)
    let priceScreen = [UInt8](repeating: 80, count: 96 * 160)
    var changedPrice = priceScreen
    changedPrice[7_111] = 160
    let originalPrice = ScreenFingerprint(samples: priceScreen)
    let updatedPrice = ScreenFingerprint(samples: changedPrice)
    precondition(originalPrice.distance(to: updatedPrice) < 0.012)
    precondition(originalPrice.hasLocalizedChange(to: updatedPrice))
    precondition(updatedPrice.hasLocalizedChange(to: originalPrice))
    precondition(!originalPrice.hasLocalizedChange(to: ScreenFingerprint(samples: [UInt8](repeating: 100, count: 96 * 160))))
    precondition(!originalPrice.hasLocalizedChange(to: originalPrice))
    precondition(originalPrice.hasLocalizedChange(to: ScreenFingerprint(samples: [80])))
    precondition(!ScreenFingerprint(samples: []).hasLocalizedChange(to: ScreenFingerprint(samples: [])))
    precondition(!fingerprint(0).hasLocalizedChange(to: fingerprint(255), threshold: 2))
    precondition(fingerprint(80).hasLocalizedChange(to: fingerprint(81), threshold: -1))
    precondition(originalPrice.hasLocalizedChange(to: updatedPrice, threshold: .nan))
    let grid = ScreenFingerprint(samples: [UInt8](repeating: 80, count: 12))
    var gridChange = [UInt8](repeating: 80, count: 12)
    gridChange[5] = 180; gridChange[10] = 180
    let changedGrid = ScreenFingerprint(samples: gridChange)
    precondition(grid.changedBounds(to: changedGrid, columns: 4, rows: 3) ==
      OCRBox(x: 0.25, y: 1.0 / 3, width: 0.5, height: 2.0 / 3))
    precondition(grid.changedBounds(to: grid, columns: 4, rows: 3) == nil)
    precondition(grid.changedBounds(to: changedGrid, columns: 4, rows: 3, threshold: 2) == nil)
    precondition(grid.changedBounds(to: changedGrid, columns: 4, rows: 3, threshold: .nan) != nil)
    let fullGrid = OCRBox(x: 0, y: 0, width: 1, height: 1)
    precondition(grid.changedBounds(to: changedGrid, columns: 0, rows: 3) == fullGrid)
    precondition(grid.changedBounds(to: changedGrid, columns: Int.max, rows: 3) == fullGrid)
    precondition(grid.changedBounds(to: fingerprint(80), columns: 4, rows: 3) == fullGrid)
    let baseArea = ScreenFingerprint(samples: Array(repeating: 80, count: 100))
    var bannerPixels = Array(repeating: UInt8(80), count: 100)
    for index in 0..<10 { bannerPixels[index] = 220 }
    let bannerA = ScreenFingerprint(samples: bannerPixels)
    near(baseArea.changedFraction(to: bannerA), 0.1)
    var animationGate = ScreenStability(settleSeconds: 0.4, changedAreaThreshold: 0.15)
    precondition(!animationGate.observe(baseArea, now: 0))
    precondition(!animationGate.observe(bannerA, now: 0.2))
    precondition(animationGate.observe(baseArea, now: 0.41))
    precondition(!animationGate.observe(bannerA, now: 1))
    var pagePixels = Array(repeating: UInt8(80), count: 100)
    for index in 0..<30 { pagePixels[index] = 220 }
    let page = ScreenFingerprint(samples: pagePixels)
    near(baseArea.changedFraction(to: page), 0.3)
    precondition(!animationGate.observe(page, now: 2))
    precondition(animationGate.observe(page, now: 2.41))
    precondition(!animationGate.observe(page, now: 3))
    var stability = ScreenStability()
    precondition(!stability.observe(fingerprint(100), now: 0))
    precondition(!stability.observe(fingerprint(102), now: 0.2))
    precondition(stability.observe(fingerprint(100), now: 0.41))
    precondition(!stability.observe(fingerprint(103), now: 1))
    precondition(!stability.observe(fingerprint(100), now: 20))
    precondition(!stability.observe(fingerprint(200), now: 21))
    precondition(!stability.observe(fingerprint(201), now: 21.2))
    precondition(stability.observe(fingerprint(200), now: 21.41))
    precondition(!stability.observe(fingerprint(200), now: 22))
    // A brief animation returning to the same delivered screen is not another result.
    precondition(!stability.observe(fingerprint(0), now: 23))
    precondition(!stability.observe(fingerprint(200), now: 23.1))
    precondition(!stability.observe(fingerprint(200), now: 24))
    stability.reset()
    precondition(!stability.observe(fingerprint(200), now: 30))
    precondition(stability.observe(fingerprint(200), now: 30.41))
    // Clock regression starts a new stability window; no elapsed-time shortcut.
    precondition(!stability.observe(fingerprint(200), now: 10))
    precondition(stability.observe(fingerprint(200), now: 10.41))
    var moving = ScreenStability()
    precondition(!moving.observe(fingerprint(0), now: 0))
    precondition(!moving.observe(fingerprint(100), now: 0.3))
    precondition(!moving.observe(fingerprint(200), now: 0.6))
    precondition(!moving.observe(fingerprint(200), now: 0.8))
    precondition(moving.observe(fingerprint(200), now: 1.01))
    print("PASS: PiP rectangular/rounded/dark-contrast/shadow/fullwidth masks, bounded diagnostics, uniqueness/density/timing/hysteresis/reset/dark-page ambiguity; half-screen exact2 boxes, unchanged30s navigation, even960wide layouts and invalid/overflow guards; revision stop/latest/session/concurrent guards; Vision clipping; all 8 EXIF non-square/corner transforms; NFC/whitespace fidelity; deterministic anchored reading rows; grayscale distance and sparse glyph change; settle/jitter/change/reset/clock semantics")
  }
}
