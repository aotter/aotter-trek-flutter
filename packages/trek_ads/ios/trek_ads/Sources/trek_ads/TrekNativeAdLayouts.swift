import AotterTrekSDK
import UIKit

/// The built-in layouts, picked by the ad's type as on Android: a Native Ad
/// gets the icon row, a Native Multimedia Ad the media card. `options` carries
/// the Dart TrekNativeAdStyle as plain values.
///
/// The call to action and the sponsor label show exactly what the ad carries;
/// an ad without a sponsor gets an "Ad" badge.
struct TrekNativeAdLayouts: TrekNativeAdFactory {
  private static let ctaBlue = UIColor(red: 0x1A / 255.0, green: 0x73 / 255.0, blue: 0xE8 / 255.0, alpha: 1)
  private static let adGreen = UIColor(red: 0x3A / 255.0, green: 0x67 / 255.0, blue: 0x28 / 255.0, alpha: 1)

  func createNativeAdView(_ ad: ATKNativeAdData, options: [String: Any]?) -> ATKNativeAdView {
    let style = options ?? [:]
    let adView = ATKNativeAdView()
    if let background = color(style["background"]) { adView.backgroundColor = background }
    let cta = callToAction(ad, style: style)
    // AotterTrekSDK wires callToActionButton only for a Native Ad. On a Native
    // Multimedia Ad an interactive button takes the tap from the ad view's own
    // tap recognizer and nothing happens, so the tap goes to the ad view for
    // both kinds, as GMA layouts do with callToActionView.
    cta.isUserInteractionEnabled = false
    if ad.adType == .native {
      stack([header(ad, style: style, iconSize: 48, end: cta)], in: adView)
    } else {
      stack([
        header(ad, style: style, iconSize: 40, end: nil),
        media(ad, in: adView),
        footer(ad, style: style, cta: cta),
      ], in: adView)
    }
    adView.callToActionButton = cta
    adView.nativeAd = ad
    return adView
  }

  private func media(_ ad: ATKNativeAdData, in adView: ATKNativeAdView) -> UIView {
    let media = ATKMediaView()
    media.imageView.contentMode = .scaleAspectFit
    // ATKMediaView has no intrinsic size. Just below the stack's bottom, so while
    // the platform view is still shorter than the layout the media shrinks
    // instead of the content leaving the ad view.
    let ratio = media.heightAnchor.constraint(equalTo: media.widthAnchor, multiplier: 1 / aspectRatio(of: ad))
    ratio.priority = .required - 2
    ratio.isActive = true
    adView.mediaView = media
    return media
  }

  /// Width over height: the creative's own size, else 16:9. (The SDK's
  /// mediaContentAspectRatio comes from the same size, so it adds nothing.)
  private func aspectRatio(of ad: ATKNativeAdData) -> CGFloat {
    let size = ad.preferredMediaViewSize
    return size.width > 0 && size.height > 0 ? size.width / size.height : 16.0 / 9.0
  }

  /// Icon, then sponsor + advertiser over the headline, then `end` if given.
  private func header(_ ad: ATKNativeAdData, style: [String: Any], iconSize: CGFloat, end: UIView?) -> UIView {
    let icon = UIImageView()
    icon.contentMode = .scaleAspectFit
    icon.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
    icon.heightAnchor.constraint(equalToConstant: iconSize).isActive = true
    if let radius = (style["cornerRadius"] as? NSNumber)?.doubleValue {
      icon.layer.cornerRadius = radius
      icon.clipsToBounds = true
    }
    // The icon keeps its place with nothing to show, so a layout's cards keep one shape.
    if let url = URL(string: ad.imgIcon), !ad.imgIcon.isEmpty {
      URLSession.shared.dataTask(with: url) { data, response, _ in
        // An error page that happens to be an image is not the icon.
        guard ((response as? HTTPURLResponse)?.statusCode ?? 200) < 300,
              let image = data.flatMap(UIImage.init(data:)) else { return }
        DispatchQueue.main.async { icon.image = image }
      }.resume()
    }

    let advertiserStyle = style["advertiser"] as? [String: Any]
    // The sponsor label takes the advertiser's color.
    let sponsor = ad.sponsor.isEmpty ? adBadge() : label(ad.sponsor, size: 11, bold: false, style: nil)
    if !ad.sponsor.isEmpty {
      sponsor.textColor = color(advertiserStyle?["textColor"]) ?? .gray
    }
    sponsor.setContentCompressionResistancePriority(.required, for: .horizontal)
    sponsor.setContentHuggingPriority(.required, for: .horizontal)
    let advertiser = label(ad.advertiserName, size: 13, bold: true, style: advertiserStyle)
    let headline = label(ad.title, size: 15, bold: true, style: style["headline"] as? [String: Any])
    headline.numberOfLines = 2

    let byline = UIStackView(arrangedSubviews: [sponsor, advertiser])
    byline.spacing = 6
    byline.alignment = .firstBaseline
    let texts = UIStackView(arrangedSubviews: [byline, headline])
    texts.axis = .vertical
    return row([icon, texts] + (end.map { [$0] } ?? []))
  }

  /// Body, then the call to action.
  private func footer(_ ad: ATKNativeAdData, style: [String: Any], cta: UIView) -> UIView {
    let body = label(ad.text, size: 13, bold: false, style: style["body"] as? [String: Any])
    body.numberOfLines = 2
    return row([body, cta])
  }

  private func callToAction(_ ad: ATKNativeAdData, style: [String: Any]) -> UIButton {
    let ctaStyle = style["callToAction"] as? [String: Any]
    let font = self.font(ctaStyle, size: 13, bold: true)
    var config = UIButton.Configuration.filled()
    config.title = ad.callToAction
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
    cta.setContentCompressionResistancePriority(.required, for: .horizontal)
    cta.setContentHuggingPriority(.required, for: .horizontal)
    NSLayoutConstraint.activate([
      cta.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
      // An empty title keeps a line's height, as on Android.
      cta.heightAnchor.constraint(greaterThanOrEqualToConstant: ceil(font.lineHeight) + 12),
    ])
    return cta
  }

  /// A green "Ad" badge, as Google's templates show one (25x20).
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

  /// A label with a TrekNativeAdTextStyle applied over the given defaults.
  private func label(_ text: String, size: CGFloat, bold: Bool, style: [String: Any]?) -> UILabel {
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
  private func stack(_ views: [UIView], in adView: ATKNativeAdView) {
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
