import AotterTrekGoogleMobileAdsMediation
import Foundation
import GoogleMobileAds
import google_mobile_ads

/// The iOS side of TrekMediationExtras (Dart). google_mobile_ads creates it by
/// this name; the single AotterTrek adapter serves AdMob and Ad Manager, so
/// every entry maps to the same AotterTrekGADMediationExtras.
@objc(TrekFlutterMediationExtras)
final class TrekFlutterMediationExtras: NSObject, FlutterMediationExtras {
  var extras: [String: Any]?

  func getMediationExtras() -> any AdNetworkExtras {
    let trek = AotterTrekGADMediationExtras()
    trek.category = extras?["Category"] as? String
    trek.contentURL = extras?["ContentUrl"] as? String
    trek.contentTitle = extras?["ContentTitle"] as? String
    return trek
  }
}
