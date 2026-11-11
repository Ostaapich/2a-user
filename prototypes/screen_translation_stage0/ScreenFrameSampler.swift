#if DEBUG || SCREEN_TRANSLATION_STAGE0 || SCREEN_TRANSLATION_LIVE
import CoreImage
import CoreVideo
import Foundation
import ImageIO

/// Bounded grayscale sampling. Core Image bitmap row zero is the oriented image's
/// top row for this rendering path (covered by actual-pixel fixture tests).
@available(iOS 27.0, *)
enum ScreenFrameSampler {
  private static let columns = 96
  private static let bitmapRows = 160
  private static let excludedRows = 8
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private static let colorSpace = CGColorSpaceCreateDeviceRGB()

  static func sample(_ image: CVPixelBuffer, orientation: CGImagePropertyOrientation, excludeStatusBar: Bool = true) -> ScreenFingerprint {
    let source = CIImage(cvPixelBuffer: image).oriented(orientation)
    let extent = source.extent
    guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else {
      return ScreenFingerprint(samples: [])
    }
    let normalized = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
      .transformed(by: CGAffineTransform(scaleX: CGFloat(columns) / extent.width,
                                       y: CGFloat(bitmapRows) / extent.height))
    var bytes = [UInt8](repeating: 0, count: columns * bitmapRows * 4)
    bytes.withUnsafeMutableBytes { storage in
      context.render(normalized, toBitmap: storage.baseAddress!, rowBytes: columns * 4,
        bounds: CGRect(x: 0, y: 0, width: columns, height: bitmapRows), format: .RGBA8, colorSpace: colorSpace)
    }
    let omittedRows = excludeStatusBar ? excludedRows : 0
    var samples: [UInt8] = []
    samples.reserveCapacity(columns * (bitmapRows - omittedRows))
    // Exclude FIRST 8 rows, not the bottom of the screen: status clock must not reset OCR.
    for offset in stride(from: columns * omittedRows * 4, to: bytes.count, by: 4) {
      samples.append(UInt8((Int(bytes[offset]) * 30 + Int(bytes[offset + 1]) * 59 + Int(bytes[offset + 2]) * 11) / 100))
    }
    return ScreenFingerprint(samples: samples)
  }

  /// Orient first, then crop in normalized top-left coordinates. The returned
  /// buffer is already upright; OCR/bbox/layout all operate in this same crop.
  static func cropped(_ image: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                      viewport: ScreenTranslationViewport) -> CVPixelBuffer? {
    let extent = CIImage(cvPixelBuffer: image).oriented(orientation).extent
    return cropped(image, orientation: orientation,
      box: viewport.box(width: extent.width, height: extent.height))
  }

  /// Crop an arbitrary normalized top-left box after orientation, without scaling.
  /// Invalid/out-of-bounds boxes fail rather than silently choosing another region.
  static func cropped(_ image: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                      box: OCRBox) -> CVPixelBuffer? {
    guard box.x.isFinite, box.y.isFinite, box.width.isFinite, box.height.isFinite,
          box.x >= 0, box.y >= 0, box.width > 0, box.height > 0,
          box.x + box.width <= 1, box.y + box.height <= 1 else { return nil }
    let oriented = CIImage(cvPixelBuffer: image).oriented(orientation)
    let extent = oriented.extent.integral
    guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { return nil }
    let rect = CGRect(x: extent.minX + box.x * extent.width,
      y: extent.minY + (1 - box.y - box.height) * extent.height,
      width: box.width * extent.width, height: box.height * extent.height).integral.intersection(extent)
    guard rect.width >= 1, rect.height >= 1 else { return nil }
    var result: CVPixelBuffer?
    guard CVPixelBufferCreate(nil, Int(rect.width), Int(rect.height), kCVPixelFormatType_32BGRA,
      [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary, &result) == kCVReturnSuccess,
      let result else { return nil }
    let cropped = oriented.cropped(to: rect)
      .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    context.render(cropped, to: result)
    return result
  }

  /// Already upright snapshot: legacy overlapping 16:9 strips, or exactly two
  /// nonoverlapping full-width half-screen parts when explicitly requested.
  /// The strips cover the full image height; no resize, persistence or OCR occurs.
  /// Invalid/over-cap geometry or any allocation failure returns nil atomically.
  static func snapshotParts(_ image: CVPixelBuffer, halfScreen: Bool = false) -> [CVPixelBuffer]? {
    let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image)
    let pages = SnapshotViewportPages(width: Double(width), height: Double(height), halfScreen: halfScreen)
    guard !pages.boxes.isEmpty else { return nil }
    if halfScreen {
      guard height >= 2, width <= 8192, height <= 8192,
            Double(width) * Double(height) <= 16_777_216 else { return nil }
      // Split in whole upright pixels. Rounding normalized half boxes outward
      // would duplicate the middle row for odd heights.
      let topHeight = height / 2
      let source = CIImage(cvPixelBuffer: image)
      let rectangles = [CGRect(x: 0, y: height - topHeight, width: width, height: topHeight),
                        CGRect(x: 0, y: 0, width: width, height: height - topHeight)]
      var halves: [CVPixelBuffer] = []
      for rectangle in rectangles {
        var result: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, Int(rectangle.height), kCVPixelFormatType_32BGRA,
          [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary, &result) == kCVReturnSuccess,
          let result else { return nil }
        let crop = source.cropped(to: rectangle)
          .transformed(by: CGAffineTransform(translationX: -rectangle.minX, y: -rectangle.minY))
        context.render(crop, to: result)
        halves.append(result)
      }
      return halves
    }
    var parts: [CVPixelBuffer] = []
    parts.reserveCapacity(pages.boxes.count)
    for box in pages.boxes {
      guard let part = cropped(image, orientation: .up, box: box) else { return nil }
      parts.append(part)
    }
    return parts
  }

  static func changedRegion(from: ScreenFingerprint, to: ScreenFingerprint, excludeStatusBar: Bool = true) -> OCRBox? {
    let omittedRows = excludeStatusBar ? excludedRows : 0
    guard let box = from.changedBounds(to: to, columns: columns, rows: bitmapRows - omittedRows) else { return nil }
    let top = Double(omittedRows) / Double(bitmapRows)
    return OCRBox(x: box.x, y: top + box.y * (1 - top), width: box.width, height: box.height * (1 - top))
  }
  /// Content-local heuristic only; protected-mask appearance must be verified on
  /// the device. No raw pixels or OCR text leave this bounded sampler.
  static func pipPosition(_ image: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                          expectedAspect: Double, now: TimeInterval,
                          detector: inout PiPPositionDetector) -> PiPVerticalPosition? {
    detector.prepareOrientation(orientation.rawValue)
    let source = CIImage(cvPixelBuffer: image).oriented(orientation)
    let extent = source.extent
    guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else {
      return detector.observe(width: 0, height: 0, luma: [], expectedAspect: expectedAspect, now: now)
    }
    let scale = min(1, min(192 / extent.width, 416 / extent.height))
    let width = max(1, Int((extent.width * scale).rounded(.down)))
    let height = max(1, Int((extent.height * scale).rounded(.down)))
    let normalized = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
      .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height))
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { storage in
      context.render(normalized, toBitmap: storage.baseAddress!, rowBytes: width * 4,
        bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: colorSpace)
    }
    var luma: [UInt8] = []
    luma.reserveCapacity(width * height)
    for offset in stride(from: 0, to: bytes.count, by: 4) {
      luma.append(UInt8((Int(bytes[offset]) * 30 + Int(bytes[offset + 1]) * 59 + Int(bytes[offset + 2]) * 11) / 100))
    }
    return detector.observe(width: width, height: height, luma: luma, expectedAspect: expectedAspect, now: now)
  }

}
#endif
