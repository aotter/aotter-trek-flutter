## 0.1.1

* `TrekMediationNativeAdWidget` no longer clashes with an app that keys its
  own widget with `GlobalObjectKey(ad)` (a duplicate `GlobalKey`).
* In an app with several Flutter engines, a native ad's height now goes to the
  engine that shows the ad. It went to the engine that registered last, which
  left the other engines' ads at `initialHeight`. On iOS, once an app has made
  a second engine, a view from the app's own `NativeAdFactory` reports its
  height only from inside a Flutter view: laid out before that, it is first
  shown at `initialHeight`.
* On iOS, ads from an app's own `NativeAdFactory` that lays its views out
  before they are shown no longer stay at `initialHeight` when several load
  before the first `TrekMediationNativeAdWidget` is built. Only the last
  height sent before then arrived; each is now sent again when its view enters
  the Flutter view.
* On iOS, creatives that move with the page are now told when it scrolls:
  `TrekMediationNativeAdWidget` tells them when the nearest `Scrollable`
  scrolls, and `TrekMediation.notifyAdScrolled()` does it by hand, for banners
  among others. The plugin now names AotterTrekSDK (5.0.1 or a later 5.x) as a
  direct dependency.
* On Android, AotterTrek now fills in release builds. Under R8 full mode the
  AotterTrek SDK's requests failed, so the mediation moved on to the next
  network as if AotterTrek had no ad. The plugin now carries the two R8 rules
  the SDK needs.
* On Android, a release build made with Android Gradle Plugin 9.1 no longer
  stops at start-up. Google Mobile Ads brings in WorkManager, whose Room
  database loses its constructor to R8; an app with `google_mobile_ads` alone
  stops the same way. The plugin now carries the rule that keeps it.
* On Android, the plugin now brings in the AotterTrek adapters 5.6.6, and with
  them `trek-ads` 5.6.6. `trek-ads` carries the two R8 rules for the SDK's
  requests itself, and the adapters carry the one for the Room database; the
  plugin keeps its own copies as well.
* The README's new Before you start section lists what to set up in the
  AotterTrek, AdMob and Ad Manager consoles.

## 0.1.0

* Brings in the AotterTrek Google Mobile Ads adapters: `trek-admob-mediation`
  and `trek-gam-mediation` on Android, `AotterTrekMediation` 5.0.1 or later on
  iOS through Swift Package Manager or CocoaPods.
* Built-in native ad layouts under factory id `trek`, registered by the plugin
  itself, and `TrekMediationNativeAdWidget`, which sizes each ad to its
  creative.
* The built-in layouts show the call to action as the ad gives it (blank when
  empty), the ad's sponsor label or Google's "Ad" badge when it has none, and
  keep the icon's place when there is no icon. Google's `NativeTemplateStyle`
  sets their colors, fonts and corner radius.
* The built-in layouts pick the icon row or the media card from the AotterTrek
  ad's own type, which the adapters report from 5.6.5 on Android and 5.0.1 on
  iOS.
* The built-in layouts follow the system text size, on iOS up to twice the
  size, and cut text that does not fit with an ellipsis.
* `TrekMediationNativeAdWidget` keeps an ad's height when a list builds its
  row again, and moves an ad's platform view with it when the ad changes rows.
* `TrekAdSizeReporter` for apps with their own `NativeAdFactory`.
* `TrekMediationExtras` for per-request category, content URL and title.
