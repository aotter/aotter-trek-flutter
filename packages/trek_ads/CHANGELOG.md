## 0.1.1

The first release. Its number matches `trek_gma_mediation`, released with it.

* `TrekAds` starts the AotterTrek SDKs (`trek-ads` 5.6.6 on Android,
  `AotterTrekSDK` 5.0.1 or a later 5.x on iOS through Swift Package Manager
  or CocoaPods) and sets the log level and the user.
* `TrekNativeAd` loads Native Ads and Native Multimedia Ads, one or up to five
  at once, with per-request category, content URL and title; its listener
  reports impressions, clicks, custom clicks, media loads and errors with the
  SDK's error code.
* `TrekNativeAdWidget` shows an ad drawn natively, sized to its layout at the
  available width. It keeps an ad's native view when a list builds its row
  again or moves the ad to another row.
* Built-in layouts: an icon row for Native Ads and a media card for Native
  Multimedia Ads, styled with `TrekNativeAdStyle`; the whole ad is clickable.
* Native ad factories in Kotlin and Swift for layouts of the app's own.
* `TrekBannerAd` and `TrekBannerAdWidget`: a banner at its creative's size,
  reloaded by the app; its listener reports impressions, clicks and media
  loads.
* On iOS, the widgets tell creatives that move with the page where they are:
  when a widget is first built for an ad, when the ad's media has loaded, and
  when the nearest `Scrollable` scrolls. `TrekAds.notifyAdScrolled` does it by
  hand, for an app that turns the automatic notice off or moves an ad some
  other way, such as by a layout change without scrolling. The notices for
  scrolling, and `TrekAds.notifyAdScrolled`, also reach AotterTrek ads shown
  through AdMob or Ad Manager.
* On Android a release build needs no R8 rules of its own: without the two
  the AotterTrek SDK needs, its requests fail under R8 full mode. `trek-ads`
  5.6.6 carries them, and so does the plugin.
