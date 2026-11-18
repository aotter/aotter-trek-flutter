# trek_ads example

AotterTrek native ads in a feed and a banner at the bottom. Every sixth row is
an ad: the first, third and fifth from a Native Multimedia Ad placement, the
second and fourth from a Native Ad placement. The built-in layouts show all of
them but the fourth, which uses the app's own layout, registered as `example`
in `MainActivity` (Android) and `AppDelegate` (iOS).

Pass your AotterTrek client id and placements in a JSON file, and never commit
it:

```sh
flutter run --dart-define-from-file=trek.local.json
```

```json
{
  "TREK_CLIENT_ID": "...",
  "NATIVE_AD_PLACE": "...",
  "NATIVE_MULTIMEDIA_AD_PLACE": "...",
  "BANNER_PLACE": "..."
}
```

To run on an iPhone, set your signing team in `ios/Flutter/Local.xcconfig`,
which git ignores:

```
DEVELOPMENT_TEAM = ...
```

Add `--dart-define=AUTO_SCROLL=true` to have the feed scroll to the end and
back twice by itself, reloading the banner in between, for runs on a device
nobody is holding.
