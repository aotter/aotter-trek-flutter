import AotterTrekSDK
import Flutter
import UIKit
import google_mobile_ads

public class TrekGmaMediationPlugin: NSObject, FlutterPlugin {
  /// How many times the plugin has been registered: once for each engine the
  /// app has made, including those that are gone.
  private static var engines = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    engines += 1
    TrekAdSizeReporter.fallback = engines == 1 ? messenger : nil
    registrar.addMethodCallDelegate(
      TrekGmaMediationPlugin(),
      channel: FlutterMethodChannel(
        name: "trek_gma_mediation/scroll", binaryMessenger: messenger))

    // Registering here rather than in the app's AppDelegate spares apps the
    // UIScene timing trap. GeneratedPluginRegistrant registers plugins in name
    // order, so google_mobile_ads is already published by now.
    if registrar.valuePublished(byPlugin: "FLTGoogleMobileAdsPlugin") == nil {
      NSLog("trek_gma_mediation: google_mobile_ads is not registered; the 'trek' native ad factory is unavailable.")
    }
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      RegistrarAsRegistry(registrar), factoryId: "trek",
      nativeAdFactory: TrekNativeAdFactory(messenger: messenger))

    // google_mobile_ads instantiates mediation extras by class name; this
    // reference keeps the class linked when the app does not use -ObjC.
    _ = TrekFlutterMediationExtras.self
  }

  // Flutter moves the native views after the frame that scrolled them, so a
  // notice from that frame finds them where they were; once the page is still,
  // one more tells them where they came to rest (measured on an iPhone XR with
  // another plugin's platform views, they were there within 33 ms; a frame
  // slower than 100 ms leaves them a frame behind until the page scrolls
  // again).
  private var restingNotice: DispatchWorkItem?

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "notifyAdScrolled" else {
      result(FlutterMethodNotImplemented)
      return
    }
    // The AotterTrek ads in the window whose creative sits in an ATKMediaView,
    // which includes those shown through AdMob or Ad Manager, banners among
    // them; the SDK tells only those that moved since last told.
    AotterTrekSDK.notifyAdScrolled()
    restingNotice?.cancel()
    let notice = DispatchWorkItem { AotterTrekSDK.notifyAdScrolled() }
    restingNotice = notice
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: notice)
    result(nil)
  }
}

/// google_mobile_ads registers factories through a FlutterPluginRegistry, but a
/// plugin only gets a registrar. Both look up published plugin values, which is
/// all registerNativeAdFactory needs.
private final class RegistrarAsRegistry: NSObject, FlutterPluginRegistry {
  private let registrar: FlutterPluginRegistrar

  init(_ registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  func registrar(forPlugin pluginKey: String) -> FlutterPluginRegistrar? { nil }

  func hasPlugin(_ pluginKey: String) -> Bool { registrar.valuePublished(byPlugin: pluginKey) != nil }

  func valuePublished(byPlugin pluginKey: String) -> NSObject? { registrar.valuePublished(byPlugin: pluginKey) }
}
