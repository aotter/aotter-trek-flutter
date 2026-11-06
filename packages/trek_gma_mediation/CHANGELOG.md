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
