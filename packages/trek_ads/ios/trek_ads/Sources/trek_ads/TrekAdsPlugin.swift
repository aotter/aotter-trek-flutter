import AotterTrekSDK
import Flutter
import UIKit

/// Builds the view for an ad, for TrekNativeAdWidget(factoryId: ...). Return an
/// ATKNativeAdView with the ad bound: for a Native Multimedia Ad, set mediaView
/// to an ATKMediaView (it has no intrinsic size; constrain its height); set
/// callToActionButton, then nativeAd last. Turn off the button's user
/// interaction: a Native Multimedia Ad does not wire callToActionButton, and an
/// interactive button there swallows the tap. Leave the view's bottom free: the
/// plugin sizes the widget to the view's fitting height at the width Flutter
/// gives it, and keeps the view for the ad's lifetime.
public protocol TrekNativeAdFactory {
  func createNativeAdView(_ ad: ATKNativeAdData, options: [String: Any]?) -> ATKNativeAdView
}

public final class TrekAdsPlugin: NSObject, FlutterPlugin, TrekAdsHostApi {
  private weak var registrar: FlutterPluginRegistrar?
  private let events: TrekAdsFlutterApi
  private var factories: [String: TrekNativeAdFactory] = [:]
  private var ads: [Int64: LoadedAd] = [:]
  private var banners: [Int64: LoadedBanner] = [:]

  init(_ registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    events = TrekAdsFlutterApi(binaryMessenger: registrar.messenger())
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = TrekAdsPlugin(registrar)
    TrekAdsHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: plugin)
    registrar.register(ViewFactory { [weak plugin] in plugin?.nativeAdView($0) ?? UIView() }, withId: nativeViewType)
    registrar.register(ViewFactory { [weak plugin] in plugin?.bannerView($0) ?? UIView() }, withId: bannerViewType)
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    TrekAdsHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    (Array(ads.keys) + Array(banners.keys)).forEach(disposeAd(adId:))
  }

  /// Makes `factory` available to TrekNativeAdWidget(factoryId: `factoryId`) in the engine of `registry`.
  public static func registerNativeAdFactory(
    _ registry: FlutterPluginRegistry, factoryId: String, factory: TrekNativeAdFactory
  ) {
    plugin(registry).factories[factoryId] = factory
  }

  public static func unregisterNativeAdFactory(_ registry: FlutterPluginRegistry, factoryId: String) {
    plugin(registry).factories[factoryId] = nil
  }

  private static func plugin(_ registry: FlutterPluginRegistry) -> TrekAdsPlugin {
    guard let plugin = registry.valuePublished(byPlugin: "TrekAdsPlugin") as? TrekAdsPlugin else {
      fatalError("TrekAdsPlugin is not registered with this engine")
    }
    return plugin
  }

  // Pop-ups and videos present from it; the SDK falls back to the top view controller.
  private var viewController: UIViewController? { registrar?.viewController }

  func initialize(clientId: String) throws {
    // The domain overrides come from Info.plist, which the SDK reads itself.
    AotterTrekSDK.sharedInstance().initSDK(clientId)
  }

  func setLogLevel(level: LogLevelMessage) throws {
    AotterTrekSDK.setLogLevel(ATKLogLevel(rawValue: level.rawValue) ?? ATKLogLevel.none)
  }

  func setUser(user: UserMessage) throws {
    AotterTrekSDK.sharedInstance().setCurrentUser(
      ATKUser(
        email: user.email ?? "", phone: user.phone ?? "", birthDay: user.birthday ?? "",
        gender: user.gender ?? "", fbId: user.fbId ?? "", firstPartyId: user.firstPartyId ?? "", meta: [:]))
  }

  func nativeSdkVersion() throws -> String { AotterTrekSDK.sdkVersion() }

  // Flutter moves the native views after the frame that scrolled them, so a
  // notice from that frame finds them where they were; once the page is still,
  // one more tells them where they came to rest (on an iPhone XR they were
  // there within 33 ms; a frame slower than 100 ms leaves them a frame behind
  // until the page scrolls again).
  private var restingNotice: DispatchWorkItem?
  // Whether the resting notice tells the other AotterTrek ads too: a notice
  // for the plugin's own ads alone does not take that from a pending one.
  private var restingTellsOthers = false

  func notifyAdScrolled() throws {
    notify(tellingOthers: true)
  }

  // Sent when a widget is first built for an ad or given another one, and
  // when an ad's media has loaded. The class method
  // records each ad's position even when the creative cannot take it yet, and
  // then skips that position; told this early, an ad shown through AdMob on
  // the same screen would miss a later notice for where it is.
  func notifyOwnAdsScrolled() throws {
    notify(tellingOthers: false)
  }

  private func notify(tellingOthers: Bool) {
    notifyViews(tellingOthers: tellingOthers)
    restingTellsOthers = tellingOthers || (restingNotice != nil && restingTellsOthers)
    restingNotice?.cancel()
    let others = restingTellsOthers
    let notice = DispatchWorkItem { [weak self] in
      self?.restingNotice = nil
      self?.notifyViews(tellingOthers: others)
    }
    restingNotice = notice
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: notice)
  }

  private func notifyViews(tellingOthers: Bool) {
    // Each of the plugin's own views first. A view's own call passes the
    // position on even when it has not changed, as after the media loads,
    // which the class method below skips; when the plugin tells only its own
    // ads, these calls are all that reach them, banners included. They also
    // reach a native ad whose creative an app's own factory hosts in a plain
    // UIView, which the class method does not.
    ads.values.forEach { $0.view?.notifyAdScrolled() }
    banners.values.forEach { $0.view.notifyAdScrolled() }
    guard tellingOthers else { return }
    // Then the other AotterTrek ads in the window whose creative sits in an
    // ATKMediaView, such as those shown through AdMob; the SDK tells only
    // those that moved since last told.
    AotterTrekSDK.notifyAdScrolled()
  }

  @MainActor
  func loadNativeAd(adId: Int64, placeUid: String, request: AdRequestMessage, customClick: Bool) async throws
    -> NativeAdMessage
  {
    try await withCheckedThrowingContinuation { result in
      // One loader per ad, so every event names its ad.
      let loaded = customClick ? CustomClickAd(adId, plugin: self) : LoadedAd(adId, plugin: self)
      loaded.pending = result
      ads[adId] = loaded
      loaded.load(placeUid, request.toATK())
    }
  }

  func isExpired(adId: Int64) throws -> Bool { ads[adId]?.ad?.isExpired ?? true }

  @MainActor
  func loadBannerAd(adId: Int64, placeUid: String, request: AdRequestMessage) async throws {
    let banner = LoadedBanner(adId, plugin: self, request: request.toATK())
    banner.view.placeID = placeUid
    banner.view.rootViewController = viewController
    banners[adId] = banner
    try await load(banner)
  }

  @MainActor
  func reloadBannerAd(adId: Int64) async throws {
    guard let banner = banners[adId] else {
      throw PigeonError(code: "load_failed", message: "The banner was disposed", details: nil)
    }
    try await load(banner)
  }

  @MainActor
  private func load(_ banner: LoadedBanner) async throws {
    try await withCheckedThrowingContinuation { result in
      banner.settle(.failure(PigeonError(code: "load_failed", message: "A newer load replaced this one", details: nil)))
      banner.pending = result
      banner.view.load(banner.request)
    }
  }

  func disposeAd(adId: Int64) {
    if let loaded = ads.removeValue(forKey: adId) {
      // Only on detach can a load still be pending.
      loaded.pending?.resume(throwing: PigeonError(code: "load_failed", message: "The ad was disposed", details: nil))
      loaded.pending = nil
      loaded.view?.removeFromSuperview()
      loaded.view?.destroy()
      loaded.ad?.destroy()
    }
    if let banner = banners.removeValue(forKey: adId) {
      banner.settle(.failure(PigeonError(code: "load_failed", message: "The banner was disposed", details: nil)))
      banner.container.removeFromSuperview()
      banner.view.destroy()
    }
  }

  fileprivate func send(_ event: @escaping @MainActor (TrekAdsFlutterApi) async throws -> Void) {
    let events = self.events
    Task { @MainActor in try? await event(events) }
  }

  /// The ad's view, built once by its factory; list recycling re-attaches the same view.
  private func nativeAdView(_ params: [String: Any]) -> UIView {
    guard let adId = (params["adId"] as? NSNumber)?.int64Value, let loaded = ads[adId], let ad = loaded.ad else {
      return UIView()
    }
    if let view = loaded.view { return view }
    let factoryId = params["factoryId"] as? String
    let factory: TrekNativeAdFactory? = if let factoryId { factories[factoryId] } else { TrekNativeAdLayouts() }
    guard let factory else {
      NSLog("trek_ads: no native ad factory registered as \"\(factoryId ?? "")\"")
      return UIView()
    }
    let view = factory.createNativeAdView(ad, options: params["options"] as? [String: Any])
    loaded.view = view
    HeightProbe.attach(to: view) { [weak self] height in self?.send { try await $0.onAdHeight(adId: adId, height: height) } }
    return view
  }

  private func bannerView(_ params: [String: Any]) -> UIView {
    guard let adId = (params["adId"] as? NSNumber)?.int64Value, let banner = banners[adId] else { return UIView() }
    return banner.container
  }

  private static let nativeViewType = "net.aotter.trek_ads/native"
  private static let bannerViewType = "net.aotter.trek_ads/banner"

  /// One native ad: its loader, then the ad, then the one view it is bound to.
  private class LoadedAd: NSObject, ATKAdLoaderDelegate {
    let id: Int64
    unowned let plugin: TrekAdsPlugin
    var loader: ATKAdLoader?
    var ad: ATKNativeAdData?
    var view: ATKNativeAdView?
    var pending: CheckedContinuation<NativeAdMessage, Error>?

    init(_ id: Int64, plugin: TrekAdsPlugin) {
      self.id = id
      self.plugin = plugin
    }

    func load(_ placeUid: String, _ request: ATKAdRequest) {
      let loader = ATKAdLoader(placeID: placeUid, listener: nil)
      loader.delegate = self
      self.loader = loader
      loader.load(request)
    }

    func adLoader(_ adLoader: ATKAdLoader, didReceive ad: ATKNativeAdData) {
      self.ad = ad
      ad.rootViewController = plugin.viewController
      pending?.resume(returning: ad.toMessage())
      pending = nil
    }

    func adLoader(_ adLoader: ATKAdLoader, didFailToReceiveAdWithError error: Error) {
      let error = error as NSError
      if let pending {
        self.pending = nil
        plugin.ads[id] = nil
        pending.resume(
          throwing: PigeonError(code: "load_failed", message: error.localizedDescription, details: Int64(error.code)))
      } else {
        // After the bind, for example 1101 for a creative the SDK cannot play.
        let id = id
        plugin.send {
          try await $0.onFailedToShow(adId: id, code: Int64(error.code), message: error.localizedDescription)
        }
      }
    }

    func adLoader(_ adLoader: ATKAdLoader, didLoadMediaFor ad: ATKNativeAdData) {
      let id = id
      plugin.send { try await $0.onMediaLoaded(adId: id) }
    }

    func adLoader(_ adLoader: ATKAdLoader, didRecordImpressionFor ad: ATKNativeAdData) {
      let id = id
      plugin.send { try await $0.onImpression(adId: id) }
    }

    func adLoader(_ adLoader: ATKAdLoader, didRecordClickFor ad: ATKNativeAdData) {
      let id = id
      plugin.send { try await $0.onClicked(adId: id) }
    }
  }

  /// Implementing didClickCustomURL is what makes the SDK hand the landing URL over.
  private final class CustomClickAd: LoadedAd {
    @objc(adLoader:didClickCustomURL:forAd:)
    func adLoader(_ adLoader: ATKAdLoader, didClickCustomURL url: String, for ad: ATKNativeAdData) {
      // The click itself arrives here instead of didRecordClickFor; Android reports it first too.
      let id = id
      plugin.send {
        try await $0.onClicked(adId: id)
        try await $0.onCustomClick(adId: id, url: url)
      }
    }
  }

  /// A banner view loads its own ads; `pending` is the load or reload Dart awaits.
  private final class LoadedBanner: NSObject, ATKBannerAdDelegate {
    let id: Int64
    unowned let plugin: TrekAdsPlugin
    let request: ATKAdRequest
    let view = ATKBannerAdView()
    /// What Flutter shows: the banner at the size the server gives it, centered, as on Android.
    let container = UIView()
    // Pinned to the size the server gives: left to intrinsic sizes, the banner
    // grows to its picture's pixel size (640x100 for a 320x50 creative).
    private lazy var width = view.widthAnchor.constraint(equalToConstant: 0)
    private lazy var height = view.heightAnchor.constraint(equalToConstant: 0)
    var pending: CheckedContinuation<Void, Error>?

    init(_ id: Int64, plugin: TrekAdsPlugin, request: ATKAdRequest) {
      self.id = id
      self.plugin = plugin
      self.request = request
      super.init()
      view.delegate = self
      view.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(view)
      NSLayoutConstraint.activate([
        view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        view.topAnchor.constraint(equalTo: container.topAnchor),
        width,
        height,
      ])
    }

    func settle(_ result: Result<Void, Error>) {
      let pending = self.pending
      self.pending = nil
      pending?.resume(with: result)
    }

    func bannerAdViewDidReceiveAd(_ bannerAdView: ATKBannerAdView) { settle(.success(())) }

    func bannerAdView(_ bannerAdView: ATKBannerAdView, didFailToReceiveAdWithError error: Error) {
      let error = error as NSError
      settle(
        .failure(PigeonError(code: "load_failed", message: error.localizedDescription, details: Int64(error.code))))
    }

    // The server decides the banner's size; it arrives before the ad shows.
    func bannerAdView(_ bannerAdView: ATKBannerAdView, willChangeAdSizeTo adSize: CGSize) {
      width.constant = adSize.width
      height.constant = adSize.height
      let id = id
      plugin.send { try await $0.onAdHeight(adId: id, height: adSize.height) }
    }

    func bannerAdViewDidLoadMedia(_ bannerAdView: ATKBannerAdView) {
      let id = id
      plugin.send { try await $0.onMediaLoaded(adId: id) }
    }

    func bannerAdViewDidRecordImpression(_ bannerAdView: ATKBannerAdView) {
      let id = id
      plugin.send { try await $0.onImpression(adId: id) }
    }

    func bannerAdViewDidRecordClick(_ bannerAdView: ATKBannerAdView) {
      let id = id
      plugin.send { try await $0.onClicked(adId: id) }
    }
  }
}

/// Hands the platform view the view the plugin keeps for the ad.
private final class ViewFactory: NSObject, FlutterPlatformViewFactory {
  private let make: ([String: Any]) -> UIView

  init(_ make: @escaping ([String: Any]) -> UIView) {
    self.make = make
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    PlatformView(make(args as? [String: Any] ?? [:]))
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
}

/// The ad's view outlives its platform view; disposeAd destroys it.
private final class PlatformView: NSObject, FlutterPlatformView {
  private let adView: UIView

  init(_ adView: UIView) {
    self.adView = adView
  }

  func view() -> UIView { adView }
}

/// Resizes with the ad view, so its layoutSubviews runs whenever Flutter
/// changes the platform view's size; reports the ad view's fitting height.
private final class HeightProbe: UIView {
  private let report: (CGFloat) -> Void
  private var reported: CGFloat = 0

  static func attach(to adView: UIView, report: @escaping (CGFloat) -> Void) {
    let probe = HeightProbe(report)
    probe.frame = adView.bounds
    probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    probe.isUserInteractionEnabled = false
    adView.insertSubview(probe, at: 0)
  }

  private init(_ report: @escaping (CGFloat) -> Void) {
    self.report = report
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
    report(height)
  }
}

extension AdRequestMessage {
  fileprivate func toATK() -> ATKAdRequest {
    ATKAdRequest(category: category ?? "", contentURL: contentUrl ?? "", contentTitle: contentTitle ?? "", meta: [:])
  }
}

extension ATKNativeAdData {
  fileprivate func toMessage() -> NativeAdMessage {
    let urls = imgs.map(\.src).filter { !$0.isEmpty }
    let size = preferredMediaViewSize
    return NativeAdMessage(
      title: title,
      body: text,
      callToAction: callToAction,
      advertiserName: advertiserName,
      sponsor: sponsor,
      category: category,
      iconUrl: imgIcon.nonEmpty,
      iconHdUrl: imgIconHd.nonEmpty,
      // The SDK's own pick: img_main, then img_banner_720x1280, then the first picture.
      mainImageUrl: imgMain.nonEmpty ?? imgs.first { $0.label == "img_banner_720x1280" }?.src.nonEmpty ?? urls.first,
      imageUrls: urls,
      mediaWidth: size.width > 0 ? Int64(size.width) : nil,
      mediaHeight: size.height > 0 ? Int64(size.height) : nil,
      // Width over height already; 0 when unknown.
      aspectRatio: mediaContentAspectRatio > 0 ? Double(mediaContentAspectRatio) : nil,
      adType: adType.message,
      isVideo: isVideoAd,
      uuid: uuid)
  }
}

extension ATKNativeAdType {
  fileprivate var message: AdTypeMessage {
    switch self {
    case .native: .native
    case .nativeMultimedia: .nativeMultimedia
    case .banner: .banner
    default: .unknown
    }
  }
}

extension String {
  fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
