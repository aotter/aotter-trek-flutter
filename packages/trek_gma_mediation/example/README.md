# trek_gma_mediation example

AotterTrek native ads in a feed, shown in the built-in layouts, and a banner.

It runs with Google's public test units and test apps as is. To see AotterTrek
fill, use your own AdMob units whose mediation groups include the AotterTrek
custom event:

- `ad_units.local.json`, passed with
  `flutter run --dart-define-from-file=ad_units.local.json`:
  `{"NATIVE_MULTIMEDIA_AD_UNIT": "...", "NATIVE_AD_UNIT": "...", "BANNER_AD_UNIT": "..."}`
- Android: `admob.appId=...` in `android/local.properties`
- iOS: `GAD_APPLICATION_ID = ...` in `ios/Flutter/Local.xcconfig`, plus
  `DEVELOPMENT_TEAM = ...` to run on a device

All three files are git-ignored.

On a test device, AdMob Network answers before AotterTrek; the home page's Ad
Inspector button opens Google's Ad Inspector, whose single ad source test
shows AotterTrek fill.

With Flutter 3.47, running or building this example (Android too, once there
is an iOS build) can fail with "Failed to copy plugin trek_gma_mediation": the
tool copies the plugin, example and its `build/` included, into
`build/ios/SourcePackages`. Delete `build/ios` (or run `flutter clean`) and try
again.
