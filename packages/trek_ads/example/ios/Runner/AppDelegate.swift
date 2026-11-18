import AotterTrekSDK
import Flutter
import UIKit
import trek_ads

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // A layout of the app's own for Native Ads (no media view), used by
    // TrekNativeAdWidget(factoryId: "example").
    TrekAdsPlugin.registerNativeAdFactory(
      engineBridge.pluginRegistry, factoryId: "example", factory: ExampleNativeAdFactory())
  }
}

struct ExampleNativeAdFactory: TrekNativeAdFactory {
  func createNativeAdView(_ ad: ATKNativeAdData, options: [String: Any]?) -> ATKNativeAdView {
    func label(_ text: String, size: CGFloat = 13, color: UIColor = .darkGray) -> UILabel {
      let label = UILabel()
      label.text = text
      label.font = .systemFont(ofSize: size)
      label.textColor = color
      label.numberOfLines = 0
      return label
    }
    let cta = UIButton(type: .system)
    cta.setTitle(ad.callToAction, for: .normal)
    cta.titleLabel?.font = .boldSystemFont(ofSize: 13)
    cta.contentHorizontalAlignment = .leading
    // The ad view takes the tap: a Native Multimedia Ad does not wire the button.
    cta.isUserInteractionEnabled = false
    let column = UIStackView(arrangedSubviews: [
      label("\(options?["label"] ?? "") · \(ad.sponsor) · \(ad.advertiserName)"),
      label(ad.title, size: 17, color: .black),
      label(ad.text),
      cta,
    ])
    column.axis = .vertical
    column.spacing = 4
    column.translatesAutoresizingMaskIntoConstraints = false

    let adView = ATKNativeAdView()
    adView.backgroundColor = UIColor(red: 1, green: 0xF8 / 255.0, blue: 0xE1 / 255.0, alpha: 1)
    adView.addSubview(column)
    // Leave the bottom free, so the plugin can size the widget to the content.
    let bottom = column.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -12)
    bottom.priority = .required - 1
    NSLayoutConstraint.activate([
      column.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
      column.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
      column.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),
      bottom,
    ])
    adView.callToActionButton = cta
    adView.nativeAd = ad
    return adView
  }
}
