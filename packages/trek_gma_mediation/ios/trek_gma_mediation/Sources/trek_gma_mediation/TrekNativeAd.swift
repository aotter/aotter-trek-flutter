import Flutter
import GoogleMobileAds
import UIKit
import google_mobile_ads

/// Tells TrekMediationNativeAdWidget (Dart) how tall an ad view's layout wants
/// to be at the width Flutter gives it, so the creative keeps its own aspect
/// ratio. Built-in layouts attach it themselves; an integrator's own
/// NativeAdFactory calls attach(_:customOptions:) with options from
/// TrekNativeAdOptions.
@objc public final class TrekAdSizeReporter: NSObject {
  // ponytail: one channel for the process; key it per engine if add-to-app needs several.
  static var channel: FlutterMethodChannel?

  @objc public static func attach(_ adView: UIView, customOptions: [AnyHashable: Any]?) {
    guard let key = customOptions?["trekSizeKey"] as? String else { return }
    let probe = LayoutProbe(key: key)
    probe.frame = adView.bounds
    probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    probe.isUserInteractionEnabled = false
    adView.insertSubview(probe, at: 0)
  }
}

/// Resizes with the ad view, so its layoutSubviews runs whenever Flutter
/// changes the platform view's size; measures the ad view's fitting height.
private final class LayoutProbe: UIView {
  let key: String
  private var reported: CGFloat = 0

  init(key: String) {
    self.key = key
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let adView = superview, adView.bounds.width > 0 else { return }
    let height = adView.systemLayoutSizeFitting(
      CGSize(width: adView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    guard height > 0, abs(height - reported) > 0.5 else { return }
    reported = height
    TrekAdSizeReporter.channel?.invokeMethod("adSize", arguments: ["key": key, "height": height])
  }
}

/// The built-in layouts behind factory id "trek": "mediaCard" or "iconRow", picked
/// by an AotterTrek ad's own type (adapter extra assets, from 5.0.1), else by
/// customOptions["trekLayout"]. customOptions["trekStyle"] carries Google's
/// NativeTemplateStyle, flattened by TrekNativeAdOptions.
///
/// Call to action shows exactly what the ad carries, blank when empty. So does the
/// sponsor label; an ad without one (other networks) gets Google's "Ad" badge, as
/// AdMob requires ad attribution.
final class TrekNativeAdFactory: NSObject, FLTNativeAdFactory {
  private static let ctaBlue = UIColor(red: 0x1A / 255.0, green: 0x73 / 255.0, blue: 0xE8 / 255.0, alpha: 1)
  private static let adGreen = UIColor(red: 0x3A / 255.0, green: 0x67 / 255.0, blue: 0x28 / 255.0, alpha: 1)

  func createNativeAd(_ nativeAd: NativeAd, customOptions: [AnyHashable: Any]?) -> NativeAdView? {
    let style = customOptions?["trekStyle"] as? [String: Any] ?? [:]
    let adView = NativeAdView()
    if let background = color(style["background"]) { adView.backgroundColor = background }
    let cta = callToAction(nativeAd, in: adView, style: style)
    if layout(for: nativeAd, chosen: customOptions?["trekLayout"] as? String ?? "mediaCard") == "iconRow" {
      stack([header(nativeAd, in: adView, style: style, iconSize: 48, end: cta)], in: adView)
    } else {
      stack([
        header(nativeAd, in: adView, style: style, iconSize: 40, end: nil),
        media(nativeAd, in: adView),
        footer(nativeAd, in: adView, style: style, cta: cta),
      ], in: adView)
    }
    adView.nativeAd = nativeAd
    TrekAdSizeReporter.attach(adView, customOptions: customOptions)
    return adView
  }

  /// The layout for the AotterTrek placement's type, which the adapter puts in
  /// the extra assets from 5.0.1; the app's choice for ads without it.
  private func layout(for ad: NativeAd, chosen: String) -> String {
    let adType = ad.extraAssets?["adType"] as? String
    let layout: String
    switch adType {
    case "NATIVE": layout = "iconRow"
    case "NATIVE_MULTIMEDIA", "BANNER": layout = "mediaCard"
    default: return chosen
    }
    if layout != chosen { NSLog("[trek_gma_mediation] %@ ad shown as %@, not the %@ asked for", adType ?? "", layout, chosen) }
    return layout
  }

  private func media(_ ad: NativeAd, in adView: NativeAdView) -> UIView {
    let media = MediaView()
    media.mediaContent = ad.mediaContent
    media.contentMode = .scaleAspectFit
    // The creative's own size (adapter extras), else mediaContent's ratio. Just
    // below the stack's bottom, so while the platform view is still shorter than
    // the layout the content shrinks instead of leaving the ad view (GMA's
    // validator flags that); above the Trek media view's own constraints.
    let ratio = media.heightAnchor.constraint(equalTo: media.widthAnchor, multiplier: 1 / aspectRatio(of: ad))
    ratio.priority = .required - 2
    ratio.isActive = true
    adView.mediaView = media
    return media
  }

  private func aspectRatio(of ad: NativeAd) -> CGFloat {
    if let w = (ad.extraAssets?["adSizeWidth"] as? NSNumber)?.doubleValue,
       let h = (ad.extraAssets?["adSizeHeight"] as? NSNumber)?.doubleValue, w > 0, h > 0 {
      return w / h
    }
    let ratio = ad.mediaContent.aspectRatio
    return ratio > 0 ? ratio : 16.0 / 9.0
  }

  /// Icon, then sponsor + advertiser over the headline, then `end` if given.
  private func header(_ ad: NativeAd, in adView: NativeAdView, style: [String: Any], iconSize: CGFloat, end: UIView?) -> UIView {
    let icon = UIImageView()
    icon.contentMode = .scaleAspectFit
    icon.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
    icon.heightAnchor.constraint(equalToConstant: iconSize).isActive = true
    if let radius = (style["cornerRadius"] as? NSNumber)?.doubleValue {
      icon.layer.cornerRadius = radius
      icon.clipsToBounds = true
    }
    // The adapter gives only a URL. The icon keeps its place with nothing to show,
    // so a layout's cards keep one shape.
    if let image = ad.icon?.image {
      icon.image = image
    } else if let url = ad.icon?.imageURL {
      URLSession.shared.dataTask(with: url) { data, response, _ in
        // An error page that happens to be an image is not the icon.
        guard ((response as? HTTPURLResponse)?.statusCode ?? 200) < 300,
              let image = data.flatMap(UIImage.init(data:)) else { return }
        DispatchQueue.main.async { icon.image = image }
      }.resume()
    }
    adView.iconView = icon

    let advertiserStyle = style["advertiser"] as? [String: Any]
    // No GMA asset slot for the sponsor label; it takes the advertiser's color.
    let sponsorText = ad.extraAssets?["Sponsor"] as? String ?? ""
    let sponsor = sponsorText.isEmpty ? adBadge() : label(sponsorText, size: 11, bold: false, style: nil)
    if !sponsorText.isEmpty {
      sponsor.textColor = color(advertiserStyle?["textColor"]) ?? .gray
    }
    sponsor.setContentCompressionResistancePriority(.required, for: .horizontal)
    sponsor.setContentHuggingPriority(.required, for: .horizontal)
    let advertiser = label(ad.advertiser, size: 13, bold: true, style: advertiserStyle)
    let headline = label(ad.headline, size: 15, bold: true, style: style["headline"] as? [String: Any])
    headline.numberOfLines = 2
    adView.advertiserView = advertiser
    adView.headlineView = headline

    let byline = UIStackView(arrangedSubviews: [sponsor, advertiser])
    byline.spacing = 6
    byline.alignment = .firstBaseline
    let texts = UIStackView(arrangedSubviews: [byline, headline])
    texts.axis = .vertical
    return row([icon, texts] + (end.map { [$0] } ?? []))
  }

  /// Body, then the call to action.
  private func footer(_ ad: NativeAd, in adView: NativeAdView, style: [String: Any], cta: UIView) -> UIView {
    let body = label(ad.body, size: 13, bold: false, style: style["body"] as? [String: Any])
    body.numberOfLines = 2
    adView.bodyView = body
    return row([body, cta])
  }

  private func callToAction(_ ad: NativeAd, in adView: NativeAdView, style: [String: Any]) -> UIView {
    let ctaStyle = style["callToAction"] as? [String: Any]
    let font = self.font(ctaStyle, size: 13, bold: true)
    var config = UIButton.Configuration.filled()
    config.title = ad.callToAction ?? ""
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = font
      return attributes
    }
    config.titleLineBreakMode = .byTruncatingTail
    config.baseForegroundColor = color(ctaStyle?["textColor"]) ?? .white
    config.baseBackgroundColor = color(ctaStyle?["backgroundColor"]) ?? Self.ctaBlue
    config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    config.cornerStyle = .fixed
    config.background.cornerRadius = (style["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 4
    let cta = UIButton(configuration: config)
    // GMA handles the tap on the registered view.
    cta.isUserInteractionEnabled = false
    cta.setContentCompressionResistancePriority(.required, for: .horizontal)
    cta.setContentHuggingPriority(.required, for: .horizontal)
    NSLayoutConstraint.activate([
      cta.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
      // An empty title keeps a line's height, as on Android.
      cta.heightAnchor.constraint(greaterThanOrEqualToConstant: ceil(font.lineHeight) + 12),
    ])
    adView.callToActionView = cta
    return cta
  }

  /// The "Ad" badge of Google's own templates (green, bold, outlined, 25x20).
  private func adBadge() -> UILabel {
    let badge = UILabel()
    badge.text = "Ad"
    badge.font = .boldSystemFont(ofSize: 10)
    badge.textAlignment = .center
    badge.textColor = Self.adGreen
    badge.layer.borderColor = Self.adGreen.cgColor
    badge.layer.borderWidth = 1
    badge.layer.cornerRadius = 3
    NSLayoutConstraint.activate([
      badge.widthAnchor.constraint(equalToConstant: 25),
      badge.heightAnchor.constraint(equalToConstant: 20),
    ])
    return badge
  }

  /// A label with Google's NativeTemplateTextStyle applied over the given defaults.
  private func label(_ text: String?, size: CGFloat, bold: Bool, style: [String: Any]?) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = font(style, size: size, bold: bold)
    // Fixed, not dynamic: a dark-mode device must not put light text on the app's light page.
    label.textColor = color(style?["textColor"]) ?? .darkGray
    // Only when given: setting nil painted the labels black on iOS 18.
    if let background = color(style?["backgroundColor"]) { label.backgroundColor = background }
    return label
  }

  private func font(_ style: [String: Any]?, size: CGFloat, bold: Bool) -> UIFont {
    let size = (style?["size"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? size
    let font: UIFont
    switch style?["fontStyle"] as? String {
    case "normal": font = .systemFont(ofSize: size)
    case "bold": font = .boldSystemFont(ofSize: size)
    case "italic": font = .italicSystemFont(ofSize: size)
    case "monospace": font = .monospacedSystemFont(ofSize: size, weight: .regular)
    default: font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    }
    // Follows the system text size as Android's sp does, up to twice the size
    // (Android's largest): the largest accessibility sizes crowd the one-row layout.
    return UIFontMetrics.default.scaledFont(for: font, maximumPointSize: size * 2)
  }

  /// Dart's ARGB32 int.
  private func color(_ value: Any?) -> UIColor? {
    guard let number = value as? NSNumber else { return nil }
    let argb = UInt32(truncatingIfNeeded: number.int64Value)
    func channel(_ shift: UInt32) -> CGFloat { CGFloat((argb >> shift) & 0xFF) / 255 }
    return UIColor(red: channel(16), green: channel(8), blue: channel(0), alpha: channel(24))
  }

  private func row(_ views: [UIView]) -> UIStackView {
    let row = UIStackView(arrangedSubviews: views)
    row.spacing = 8
    row.alignment = .center
    row.isLayoutMarginsRelativeArrangement = true
    row.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    // Else the margins grow by the safe area while the ad scrolls under the status bar, and so does the reported height.
    row.insetsLayoutMarginsFromSafeArea = false
    return row
  }

  /// Pins the views top-down; the bottom is open so the fitting height is the content's.
  private func stack(_ views: [UIView], in adView: NativeAdView) {
    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = .vertical
    stack.translatesAutoresizingMaskIntoConstraints = false
    adView.addSubview(stack)
    // Below required: the platform view starts shorter than the content (even
    // zero high), and a required bottom would log an unsatisfiable-constraints
    // warning. Above everything else, so the content gives way instead.
    let bottom = stack.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor)
    bottom.priority = .required - 1
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: adView.topAnchor),
      stack.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
      bottom,
    ])
  }
}
