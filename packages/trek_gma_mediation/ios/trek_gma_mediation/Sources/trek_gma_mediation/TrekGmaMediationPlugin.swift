import Flutter
import UIKit
import google_mobile_ads

public class TrekGmaMediationPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    TrekAdSizeReporter.channel = FlutterMethodChannel(
      name: "trek_gma_mediation/ad_size", binaryMessenger: registrar.messenger())

    // Registering here rather than in the app's AppDelegate spares apps the
    // UIScene timing trap. GeneratedPluginRegistrant registers plugins in name
    // order, so google_mobile_ads is already published by now.
    if registrar.valuePublished(byPlugin: "FLTGoogleMobileAdsPlugin") == nil {
      NSLog("trek_gma_mediation: google_mobile_ads is not registered; the 'trek' native ad factory is unavailable.")
    }
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      RegistrarAsRegistry(registrar), factoryId: "trek", nativeAdFactory: TrekNativeAdFactory())

    // google_mobile_ads instantiates mediation extras by class name; this
    // reference keeps the class linked when the app does not use -ObjC.
    _ = TrekFlutterMediationExtras.self
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
