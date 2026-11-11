#if SCREEN_TRANSLATION_LIVE
import Flutter
import SwiftUI
import UIKit
import CoreText

/// Private Flutter transport. Credentials never enter URLs, logs or shared files.
enum ScreenTranslationLiveBridge {
  private static var channel: FlutterMethodChannel?
  private static var closeSession: (() -> Void)?
  private static var presentationID: UUID?

  static func install(messenger: FlutterBinaryMessenger) {
    let transport = FlutterMethodChannel(name: "com.twoalogistic.user/screen_translation", binaryMessenger: messenger)
    channel = transport
    transport.setMethodCallHandler { call, result in
      DispatchQueue.main.async {
        switch call.method {
        case "stop":
          closeSession?(); closeSession = nil; presentationID = nil; result(nil)
        case "present":
          guard #available(iOS 27.0, *) else {
            result(FlutterError(code: "UNSUPPORTED_IOS", message: "iOS 27 is required", details: nil)); return
          }
          guard closeSession == nil else {
            result(FlutterError(code: "SESSION_ACTIVE", message: "Screen translation is already open", details: nil)); return
          }
          guard let args = call.arguments as? [String: Any], Set(args.keys).isSubset(of: ["endpoint", "accessToken", "appearance"]),
                let endpointString = args["endpoint"] as? String, let endpoint = URL(string: endpointString),
                endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil,
                endpoint.query == nil, endpoint.fragment == nil, endpoint.path.hasSuffix("/screen-translate/v1"),
                let token = args["accessToken"] as? String, !token.isEmpty, token.count <= 16_384,
                let appearance = ScreenTranslationAppearance.parse(args["appearance"]) else {
            result(FlutterError(code: "INVALID_SESSION", message: "Invalid translation session", details: nil)); return
          }
          present(endpoint: endpoint, token: token, appearance: appearance, result: result)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  @available(iOS 27.0, *)
  private static func present(endpoint: URL, token: String, appearance: ScreenTranslationAppearance, result: @escaping FlutterResult) {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }),
      let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "UI_UNAVAILABLE", message: "Application is not active", details: nil)); return
    }
    var presenter = root
    while let next = presenter.presentedViewController { presenter = next }
    guard !presenter.isBeingDismissed, !presenter.isBeingPresented else {
      result(FlutterError(code: "UI_UNAVAILABLE", message: "Application is transitioning", details: nil)); return
    }
    let currentPresentation = UUID()
    presentationID = currentPresentation
    let credentials = ScreenLiveCredentials(endpoint: endpoint, token: token)
    // Match the content geometry to half the current scene, rather than a
    // hard-coded landscape video. iOS still chooses the external PiP bounds.
    let screenSize = scene.coordinateSpace.bounds.size
    let safeArea = scene.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets ?? .zero
    guard let layout = HalfScreenPiPLayout(screenWidth: Double(screenSize.width), screenHeight: Double(screenSize.height),
      safeAreaTop: Double(safeArea.top), safeAreaBottom: Double(safeArea.bottom)) else {
      presentationID = nil
      result(FlutterError(code: "UI_UNAVAILABLE", message: "Invalid screen geometry", details: nil)); return
    }
    let model = ProbeModel(halfScreenLayout: layout)
    model.pip.progressLabel = appearance.language == "zh" ? "翻译中…" : "Переводим…"
    model.configureLive { credentials.makeClient() }
    model.onUnauthorized = { credentials.clear() }
    var host: UIHostingController<ScreenTranslationLiveView>?
    host = UIHostingController(rootView: ScreenTranslationLiveView(model: model, appearance: appearance) {
      model.stop(); credentials.clear()
      host?.dismiss(animated: true) {
        host = nil
        if presentationID == currentPresentation { closeSession = nil; presentationID = nil }
      }
    })
    guard let controller = host else { return }
    controller.modalPresentationStyle = .fullScreen
    controller.isModalInPresentation = true
    closeSession = { [weak model, weak controller] in
      presentationID = nil
      model?.stop(); credentials.clear()
      controller?.dismiss(animated: true)
      host = nil
    }
    presenter.present(controller, animated: true) {
      guard presentationID == currentPresentation else { return }
      model.beginLive()
    }
    result(nil)
  }
}

@available(iOS 27.0, *)
private struct ScreenTranslationAppearance {
  let primary: Color
  let secondary: Color
  let gradientStart: Color
  let language: String
  var gradient: LinearGradient { LinearGradient(colors: [gradientStart, secondary], startPoint: .topLeading, endPoint: .bottomTrailing) }
  static func parse(_ raw: Any?) -> Self? {
    guard let raw else {
      return Self(primary: color(0xFF6B7280), secondary: color(0xFF9CA3AF), gradientStart: color(0xFF4B5563), language: Locale.current.language.languageCode?.identifier ?? "ru")
    }
    guard let values = raw as? [String: Any], Set(values.keys) == ["primary", "secondary", "gradientStart", "language"],
          let primary = argb(values["primary"]), let secondary = argb(values["secondary"]),
          let start = argb(values["gradientStart"]), let language = values["language"] as? String,
          language.range(of: "^[a-z]{2,3}$", options: .regularExpression) != nil else { return nil }
    return Self(primary: color(primary), secondary: color(secondary), gradientStart: color(start), language: language)
  }
  private static func argb(_ raw: Any?) -> UInt32? {
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue >= 0, number.doubleValue <= Double(UInt32.max),
          number.doubleValue.rounded() == number.doubleValue else { return nil }
    return number.uint32Value
  }
  private static func color(_ argb: UInt32) -> Color {
    Color(.sRGB, red: Double((argb >> 16) & 255) / 255, green: Double((argb >> 8) & 255) / 255,
      blue: Double(argb & 255) / 255, opacity: Double((argb >> 24) & 255) / 255)
  }
}

/// Reuses the font assets already shipped by Flutter; no duplicate font files.
private enum TranslationFont {
  private static let names: [String: String] = {
    var result: [String: String] = [:]
    for weight in ["Regular", "SemiBold", "Bold", "Black"] {
      let path = "Frameworks/App.framework/flutter_assets/assets/fonts/gilroy/Gilroy-\(weight).ttf"
      let url = Bundle.main.bundleURL.appendingPathComponent(path)
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
         let first = descriptors.first,
         let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String {
        result[weight] = name
      }
    }
    return result
  }()
  static func font(_ size: CGFloat, _ weight: String = "Regular") -> Font {
    guard let name = names[weight] else { return .system(size: size, weight: weight == "Regular" ? .regular : .semibold) }
    return .custom(name, size: size, relativeTo: .body)
  }
}

@available(iOS 27.0, *)
private final class ScreenLiveCredentials {
  private let endpoint: URL
  private var token: String
  init(endpoint: URL, token: String) { self.endpoint = endpoint; self.token = token }
  func makeClient() -> ScreenTranslationClient? {
    guard !token.isEmpty else { return nil }
    return ScreenTranslationClient(endpoint: endpoint, bearerToken: token)
  }
  func clear() { token = "" }
  deinit { clear() }
}

@available(iOS 27.0, *)
private struct ScreenTranslationLiveView: View {
  @StateObject private var model: ProbeModel
  let close: () -> Void
  private let appearance: ScreenTranslationAppearance

  init(model: ProbeModel, appearance: ScreenTranslationAppearance, close: @escaping () -> Void) {
    _model = StateObject(wrappedValue: model); self.appearance = appearance; self.close = close
  }
  private func text(_ ru: String, _ zh: String) -> String { appearance.language == "zh" ? zh : ru }

  private var status: String {
    if ["unauthorized", "auth_required"].contains(model.state) { return text("Войдите в аккаунт заново", "请重新登录账户") }
    if !model.running {
      switch model.state {
      case "session_expired": return text("Сессия завершена. Запустите переводчик снова.", "会话已结束，请重新启动翻译器。")
      case "access_expired": return text("Пробный доступ закончился. Для продолжения нужно поступление на наш склад за последние 30 дней.", "试用已结束，继续使用需在最近30天内有货物入库。")
      case "off": return text("Подготавливаем переводчик…", "正在准备翻译器…")
      case "session_stopped", "capture_stopped": return text("Переводчик остановлен", "翻译器已停止")
      case "capture_cancelled": return text("Запуск отменён", "已取消启动")
      case "pip_automatic_start_unavailable": return text("Окно не открылось. Проверьте автозапуск PiP в настройках iOS и повторите.", "窗口未打开。请检查iOS画中画自动启动设置，然后重试。")
      default: return text("Не удалось запустить переводчик. Повторите запуск.", "无法启动翻译器，请重试。")
      }
    }
    if model.state == "checking_access" { return text("Проверяем доступ…", "正在检查使用权限…") }
    if model.state == "permission_required" { return text("Разрешите трансляцию в системном окне", "请在系统窗口中允许屏幕共享") }
    if !model.automaticPiPArmed { return text("Подготавливаем окно перевода…", "正在准备翻译窗口…") }
    switch model.ocrState {
    case "translation_failed", "translation_timeout": return text("Не удалось перевести экран", "画面翻译失败")
    case "layout_partial": return text("Отдельные подписи не поместились. Можно повторить перевод.", "部分文字无法完整显示，可重试翻译。")
    case "layout_failed": return text("Не удалось отобразить снимок. Повторите перевод.", "无法显示画面，请重试翻译。")
    case "no_network": return text("Нет соединения с интернетом", "无法连接互联网")
    case "rate_limited": return text("Повторите перевод немного позже", "请稍后重试翻译")
    case "translated_partial": return text("Часть текста требует повторного перевода", "部分文字需要重新翻译")
    default: return text("Готово. Откройте нужное приложение", "已准备好，请打开需要翻译的应用")
    }
  }

  private let ink = Color(red: 17/255, green: 17/255, blue: 17/255)
  private let muted = Color(red: 107/255, green: 114/255, blue: 128/255)

  private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content().padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20))
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.6), lineWidth: 0.8))
      .shadow(color: .black.opacity(0.045), radius: 12, x: 0, y: 7)
  }

  private func instruction(_ icon: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon).font(.system(size: 18, weight: .semibold))
        .foregroundStyle(appearance.primary).frame(width: 38, height: 38)
        .background(appearance.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(TranslationFont.font(15, "SemiBold")).foregroundStyle(ink)
        Text(detail).font(TranslationFont.font(13)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(TranslationFont.font(15, "SemiBold")).foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 15)
        .background(appearance.gradient, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: appearance.primary.opacity(0.22), radius: 4, x: 0, y: 4)
    }.buttonStyle(.plain)
  }

  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(red: 242/255, green: 242/255, blue: 247/255),
        Color(red: 232/255, green: 240/255, blue: 255/255), Color(red: 245/255, green: 230/255, blue: 255/255)],
        startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Button(action: close) {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(ink)
              .frame(width: 46, height: 44).background(.white, in: RoundedRectangle(cornerRadius: 16))
              .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.035)))
          }.buttonStyle(.plain).accessibilityLabel(text("Назад и остановить переводчик", "返回并停止翻译器"))
          Text(text("Переводчик", "翻译器")).font(TranslationFont.font(26, "Black")).foregroundStyle(ink)
          Spacer(minLength: 0)
        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 18)

        ScrollView {
          VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: "character.bubble.fill").font(.system(size: 25))
                .frame(width: 46, height: 46).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 17))
              VStack(alignment: .leading, spacing: 6) {
                Text(text("Китайский → Русский", "中文 → 俄文")).font(TranslationFont.font(21, "Black"))
                Text(text("Перевод поверх других приложений", "在其他应用上方显示翻译")).font(TranslationFont.font(13, "SemiBold")).opacity(0.9)
              }
              Spacer(minLength: 0)
            }.foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
              .background(appearance.gradient, in: RoundedRectangle(cornerRadius: 24))
              .shadow(color: appearance.primary.opacity(0.17), radius: 10, x: 0, y: 7)

            surface {
              VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 9) {
                  Circle().fill(model.running ? appearance.primary : muted).frame(width: 8, height: 8).padding(.top, 5)
                  Text(status).font(TranslationFont.font(15, "SemiBold")).foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("screenTranslationStatus")
                }
                ScreenTranslationLayerPreview(layer: model.pip.layer)
                  .aspectRatio(model.pip.previewAspectRatio, contentMode: .fit)
                  .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                  .clipShape(RoundedRectangle(cornerRadius: 14)).id(ObjectIdentifier(model.pip))
              }
            }

            surface {
              VStack(alignment: .leading, spacing: 18) {
                Text(text("Как пользоваться", "使用方法")).font(TranslationFont.font(17, "Bold")).foregroundStyle(ink)
                instruction("arrow.up.forward.app", text("Откройте нужное приложение", "打开需要翻译的应用"),
                  text("После разрешения захвата окно перевода появится автоматически при выходе из 2A.", "允许屏幕捕获后，离开2A时会自动显示翻译窗口。"))
                instruction("backward.end.fill", text("Управляйте переводом в окне", "在窗口中控制翻译"),
                  text("Переместите окно вверх или вниз — перевод переключится на противоположную половину. Пауза фиксирует перевод.", "将窗口移到上方或下方，翻译会切换到另一半画面。暂停可固定翻译。"))
              }
            }

            surface {
              Text(text("Первые 14 дней с первого запуска — пробный доступ. Затем переводчик доступен при поступлении на наш склад за последние 30 дней.", "首次启动后可试用14天，之后需在最近30天内有货物入库方可使用。"))
                .font(TranslationFont.font(13)).foregroundStyle(muted)
            }
            VStack(spacing: 12) {
              if model.canRetryTranslation { primaryButton(text("Повторить перевод", "重试翻译")) { model.retryTranslation() } }
              if model.running {
                Button { model.stop() } label: {
                  HStack(spacing: 8) {
                    Image(systemName: "stop.circle").font(.system(size: 19))
                    Text(text("Остановить переводчик", "停止翻译器")).font(TranslationFont.font(15, "SemiBold"))
                  }.foregroundStyle(Color(red: 229/255, green: 57/255, blue: 53/255))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.red.opacity(0.15)))
                }.buttonStyle(.plain)
              } else { primaryButton(text("Запустить переводчик", "启动翻译器")) { model.beginLive() } }
            }.padding(.top, 4)
            Text(text("Текст распознаётся на iPhone и передаётся в 2A и Яндекс для перевода. Закрытие PiP останавливает переводчик.", "文字在iPhone本地识别，并发送到2A及Yandex进行翻译。关闭画中画即停止翻译器。"))
              .font(TranslationFont.font(12)).foregroundStyle(muted).multilineTextAlignment(.center).padding(.horizontal, 4)
          }.padding(.horizontal, 20).padding(.bottom, 28)
        }
      }
    }.tint(appearance.primary).environment(\.locale, Locale(identifier: appearance.language))
  }

}
@available(iOS 27.0, *)
private struct ScreenTranslationLayerPreview: UIViewRepresentable {
  let layer: CALayer
  func makeUIView(context: Context) -> ScreenTranslationLayerView { ScreenTranslationLayerView(display: layer) }
  func updateUIView(_ view: ScreenTranslationLayerView, context: Context) {}
}
@available(iOS 27.0, *)
private final class ScreenTranslationLayerView: UIView {
  let display: CALayer
  init(display: CALayer) { self.display = display; super.init(frame: .zero); layer.addSublayer(display) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func layoutSubviews() { super.layoutSubviews(); display.frame = bounds }
}
#endif
