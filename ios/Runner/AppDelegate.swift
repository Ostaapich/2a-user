import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import Vision
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Явная инициализация Firebase
    FirebaseApp.configure()

    // Регистрация для push-уведомлений
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "com.twoalogistic.user.notification_badge") {
      let channel = FlutterMethodChannel(
        name: "com.twoalogistic.user/notification_badge",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "setCount",
              let arguments = call.arguments as? [String: Any],
              let count = arguments["count"] as? Int else {
          result(FlutterMethodNotImplemented)
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.applicationIconBadgeNumber = max(0, count)
          result(nil)
        }
      }
    }

    if let registrar = self.registrar(forPlugin: "com.twoalogistic.user.video_playback") {
      let channel = FlutterMethodChannel(
        name: "com.twoalogistic.user/video_playback",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "playAvailable" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let arguments = call.arguments as? [String: Any],
          let identifier = arguments["playerId"] as? NSNumber,
          let plugin = self?.valuePublished(byPlugin: "FVPVideoPlayerPlugin") as? NSObject,
          plugin.responds(to: NSSelectorFromString("playersByIdentifier")),
          let players = plugin.value(forKey: "playersByIdentifier") as? NSDictionary,
          let wrapper = players[identifier] as? NSObject,
          wrapper.responds(to: NSSelectorFromString("player")),
          let player = wrapper.value(forKey: "player") as? AVPlayer
        else {
          result(FlutterError(code: "PLAYER_UNAVAILABLE", message: "Video player is unavailable", details: nil))
          return
        }
        // Scope this to the requested report player. Keep plugin-owned players
        // and their authentication/Range requests; do not change global policy.
        player.automaticallyWaitsToMinimizeStalling = false
        player.currentItem?.preferredForwardBufferDuration = 3
        let rate = (arguments["rate"] as? NSNumber)?.floatValue ?? 1
        player.playImmediately(atRate: rate)
        result(nil)
      }
    }
    if let registrar = self.registrar(forPlugin: "com.twoa.visual_effect_view") {
      registrar.register(VisualEffectViewFactory(messenger: registrar.messenger()), withId: "com.twoa.visual_effect_view")
    }
    if let registrar = self.registrar(forPlugin: "com.twoalogistic.user.text_recognition") {
      let channel = FlutterMethodChannel(
        name: "com.twoalogistic.user/text_recognition",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "recognizeText" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          !path.isEmpty
        else {
          result(FlutterError(code: "NO_PATH", message: "Image path is required", details: nil))
          return
        }
        Self.recognizeText(at: path, result: result)
      }
    }

    #if SCREEN_TRANSLATION_LIVE
    if let registrar = self.registrar(forPlugin: "com.twoalogistic.user.screen_translation") {
      ScreenTranslationLiveBridge.install(messenger: registrar.messenger())
    }
    #endif

    // Регистрация для удалённых уведомлений
    application.registerForRemoteNotifications()

    #if DEBUG || SCREEN_TRANSLATION_STAGE0
    ScreenTranslationDebugPresenter.install()
    #endif

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func recognizeText(at path: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      let imageURL = URL(fileURLWithPath: path)
      guard FileManager.default.fileExists(atPath: imageURL.path) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "IMAGE_NOT_FOUND", message: "Selected image was not found", details: nil))
        }
        return
      }

      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = false
      request.recognitionLanguages = ["zh-Hans", "en-US"]

      do {
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        try handler.perform([request])
        let text = (request.results ?? [])
          .compactMap { $0.topCandidates(1).first?.string }
          .joined(separator: "\n")
        DispatchQueue.main.async { result(text) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
  
  // Получение APNs токена
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("📱 APNs device token received")
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // Ошибка регистрации
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Failed to register for remote notifications: \(error)")
  }
}

class SceneDelegate: FlutterSceneDelegate {}

// MARK: - UIVisualEffectView PlatformView

class VisualEffectViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return VisualEffectPlatformView(frame: frame, viewId: viewId, args: args)
  }
}

private class VisualEffectPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect, viewId: Int64, args: Any?) {
    self.container = UIView(frame: frame)
    super.init()

    container.backgroundColor = .clear
    container.isOpaque = false
    container.clipsToBounds = true

    var cornerRadius: CGFloat = 20
    var material: UIBlurEffect.Style = .systemMaterial

    if let dict = args as? [String: Any] {
      if let radius = dict["cornerRadius"] as? NSNumber {
        cornerRadius = CGFloat(truncating: radius)
      }
      if let styleStr = dict["style"] as? String {
        material = Self.parseStyle(styleStr)
      }
    }

    container.layer.cornerRadius = cornerRadius

    let blur = UIBlurEffect(style: material)
    let blurView = UIVisualEffectView(effect: blur)
    blurView.frame = container.bounds
    blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blurView.backgroundColor = .clear
    blurView.isOpaque = false
    container.addSubview(blurView)
  }

  func view() -> UIView { container }

  private static func parseStyle(_ value: String) -> UIBlurEffect.Style {
    switch value {
    case "systemUltraThinMaterial": return .systemUltraThinMaterial
    case "systemThinMaterial": return .systemThinMaterial
    case "systemMaterial": return .systemMaterial
    case "systemThickMaterial": return .systemThickMaterial
    case "systemChromeMaterial": return .systemChromeMaterial
    case "regular": return .regular
    case "prominent": return .prominent
    default:
      if #available(iOS 13.0, *) {
        return .systemMaterial
      } else {
        return .regular
      }
    }
  }
}
