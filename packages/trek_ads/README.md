# trek_ads

[AotterTrek](https://aotter.net) ads in Flutter, straight from the AotterTrek
SDKs: Native Ads, Native Multimedia Ads and banners, with no ad network in
between.

The AotterTrek SDKs draw the ads in native views, so Open Measurement measures
them as in a native app; Flutter only passes colors and fonts. The built-in
layouts size themselves to each creative, and an app can register layouts of
its own in Kotlin and Swift.

For AotterTrek through AdMob or Ad Manager mediation, use `trek_gma_mediation`
instead.

The integration guide is at
[aotter.gitbook.io/flutter](https://aotter.gitbook.io/flutter).

## Requirements

- Flutter 3.47.1 or later.
- iOS 15 or later.
- Android `minSdk` 24. The app's `MainActivity` **must extend
  `FlutterFragmentActivity`**: the AotterTrek SDK depends on `FragmentActivity`
  and degrades silently without it.
- Android apps declare Aotter's Maven repository in their own Gradle
  configuration; repositories declared inside a plugin do not reach the app:

  ```kotlin
  maven { url = uri("https://deps.aotter.net/artifactory/libs-release-local") }
  ```

## Getting started

```dart
await TrekAds.initialize('<your client id>');
```

`TrekAds.setLogLevel` controls the SDKs' logging. `TrekAds.setUser` attaches
user signals for targeting; the SDKs hash the email and phone themselves.
AotterTrek keeps a user once set, so `TrekAds.removeUser` does nothing.

On iOS, an app that also uses AotterTrek's MyApp service initializes the SDK
with it in native code first and passes the same client id to
`TrekAds.initialize`: another id starts the SDK again without MyApp.

## Native ads

```dart
final ad = await TrekNativeAd.load(
  '<your place uid>',
  request: const TrekAdRequest(
    category: 'news',
    contentUrl: 'https://example.com/article/1',
    contentTitle: 'Article title',
  ),
  listener: TrekNativeAdListener(
    onImpression: (ad) {},
    onClicked: (ad) {},
  ),
);

// In the widget tree:
TrekNativeAdWidget(ad: ad);

// When done with it:
await ad.dispose();
```

`load` throws a `TrekAdError` when there is no ad to show.
`TrekNativeAd.loadMany` loads 1 to 5 ads at once and fails only when every
load does.

Show an ad in one place at a time. It keeps its native view while a list
scrolls it away and back, or moves it to another row, until `dispose`.

`TrekNativeAdWidget` takes the height its layout needs at the available width;
do not wrap it in a fixed-height box. Until the layout reports its height, the
widget is `initialHeight` tall (300 by default).

The built-in layouts give a Native Ad an icon row and a Native Multimedia Ad a
card with the creative at its own aspect ratio. They show the call to action
as the ad gives it, the ad's sponsor label or an "Ad" badge when it has none,
and the whole ad is clickable. `TrekNativeAdStyle` sets their colors and fonts:

```dart
TrekNativeAdWidget(
  ad: ad,
  style: TrekNativeAdStyle(
    backgroundColor: Colors.white,
    cornerRadius: 8,
    callToAction: TrekNativeAdTextStyle(backgroundColor: Colors.teal),
  ),
);
```

| `TrekNativeAdStyle` | Applies to |
|---|---|
| `backgroundColor` | the ad's background |
| `cornerRadius` | the icon and the call to action |
| `headline` | the headline |
| `advertiser` | the advertiser (the sponsor label takes its text color) |
| `body` | the body |
| `callToAction` | the call to action |

The ad's fields (`title`, `body`, `mainImageUrl` and so on) are for reference:
an ad counts impressions and clicks only when shown in `TrekNativeAdWidget`.

## Layouts of your own

Register a native ad factory on each platform and name it in `factoryId`;
`options` reaches the factory as plain values:

```dart
TrekNativeAdWidget(ad: ad, factoryId: 'my_layout', options: {'label': 'Sponsored'});
```

Android, in `MainActivity.configureFlutterEngine`, after
`super.configureFlutterEngine`, which registers the plugin:

```kotlin
TrekAdsPlugin.registerNativeAdFactory(flutterEngine, "my_layout") { activity, ad, options ->
    TrekNativeAdView(activity).apply {
        addView(content, MATCH_PARENT, WRAP_CONTENT)
        setNativeAd(ad)
        ad.setNativeAdClickAction(this)
    }
}
```

- `TrekNativeAdView` is a `ConstraintLayout`: add the content with
  `MATCH_PARENT` width.
- For a Native Multimedia Ad, add a `TrekMediaView` and call `setTrekMediaView`
  before `setNativeAd`. Never put a `TrekMediaView` in a Native Ad.
- Hand the views that click through to `ad.setNativeAdClickAction`: the whole
  `TrekNativeAdView`, as the built-in layouts do, and any clickable view inside
  it, such as a `Button`, which otherwise keeps the tap.

iOS, in an `AppDelegate` that adopts `FlutterImplicitEngineDelegate`:

```swift
import AotterTrekSDK
import trek_ads

func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
  GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  TrekAdsPlugin.registerNativeAdFactory(
    engineBridge.pluginRegistry, factoryId: "my_layout", factory: MyLayout())
}

struct MyLayout: TrekNativeAdFactory {
  func createNativeAdView(_ ad: ATKNativeAdData, options: [String: Any]?) -> ATKNativeAdView {
    let adView = ATKNativeAdView()
    // Add and constrain the content, leaving the bottom free.
    callToAction.isUserInteractionEnabled = false
    adView.callToActionButton = callToAction
    adView.nativeAd = ad
    return adView
  }
}
```

- For a Native Multimedia Ad, set `mediaView` to an `ATKMediaView`. It has no
  intrinsic size: constrain its height, for example with the ad's aspect ratio.
- Turn off the call to action's user interaction. A Native Multimedia Ad does
  not wire `callToActionButton`, and an interactive button there swallows the
  tap; the SDK makes the whole ad view clickable.
- Set `mediaView` and `callToActionButton` before `nativeAd`.
- Leave the bottom free: the plugin sizes the widget to the view's fitting
  height at the width Flutter gives it.

On both platforms the plugin builds an ad's view once, when the ad is first
shown, and keeps it for the ad's lifetime: `style`, `factoryId` and `options`
apply as they were then.

## Banners

```dart
final banner = await TrekBannerAd.load(
  '<your place uid>',
  listener: TrekBannerAdListener(onImpression: (_) {}, onClicked: (_) {}),
);

TrekBannerAdWidget(ad: banner);

await banner.reload(); // the next ad; the current one stays if this fails
await banner.dispose();
```

An AotterTrek banner placement has one size. The widget takes the creative's
size, centered in the available width. Banners do not refresh by themselves:
call `reload` on a schedule of your own. A reload started while another is
pending ends the earlier one with a `TrekAdError`.

## Events and errors

- `onImpression` is AotterTrek's viewable impression. On iOS, a video ad
  reports it again each time the video replays, by the SDK's design.
- `onClicked` reports clicks on the ad. Giving `onCustomClick` takes clicks over
  for ads that allow it: the SDK counts the click and hands the landing URL to
  the app instead of opening it, after `onClicked`. Links inside a creative can
  still open by themselves: on Android those of a WebView creative and its
  pop-up, on iOS those of a video, an HTML5 creative and a WebView creative's
  pop-up.
- An exception a listener throws synchronously goes to `FlutterError.onError`.
- `onMediaLoaded` comes once when the picture or creative has loaded in the
  ad's media view, so a native ad layout without one does not get it. Banners
  report it too.
- `onFailedToShow` (iOS only) is an error after the ad was shown, such as 1101
  for a creative the SDK cannot play.
- `TrekAdError.code` is the SDK's error code, the same on both platforms: 800
  (no ad), 900 (server or other failure), 901 (not initialized) and 1000 (no
  placement). iOS has a few more, listed in the AotterTrek iOS SDK's README.
  It is null when no SDK code applies, such as a failed initialize on Android
  or a reload that a newer one replaced.

## Scrolling

On Android, a Native Multimedia Ad and a banner hold the video player's
`SurfaceView`, so Flutter shows them with hybrid composition, as
`google_mobile_ads` does for such views. A long list with several of them
scrolls less smoothly, and the overscroll stretch does not reach them: the
list stretches while the ad stays put. If that shows, turn the stretch off
for lists with ads:

```dart
ScrollConfiguration(
  behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
  child: listView,
);
```

Creatives that move with the page follow scrolling by themselves on Android. On
iOS they need telling where they are: `TrekNativeAdWidget` tells them when it
is first built for an ad, when the ad's media has loaded, and whenever the
nearest `Scrollable` around the ad scrolls (`notifyScrollAutomatically`, on by
default), and so does `TrekBannerAdWidget`. Call `TrekAds.notifyAdScrolled`
yourself when an ad moves or comes into view some other way: with an outer
`Scrollable`, when the layout above it changes without scrolling, or when a
page built out of sight, such as a tab, is brought forward. With the automatic
notice off, also call it after `onMediaLoaded`, after the frame in which an ad
is shown again somewhere else, and as the page scrolls. On iOS the notices for
scrolling, and `TrekAds.notifyAdScrolled`, also reach AotterTrek ads shown
through AdMob or Ad Manager on the same screen; the notices when an ad is
shown or its media has loaded reach only this package's ads.
Creatives that move with the page have been watched following the page on an
iPhone and on an Android phone.

## iOS with CocoaPods

Swift Package Manager is the default. An app that uses CocoaPods instead adds
Aotter's spec repository, where AotterTrek publishes its iOS pods, to
`ios/Podfile`:

```ruby
source 'https://github.com/aotter/AotterTrekSpecs-iOS.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '15.0'
```

## Compatibility

Tested with:

| | Version |
|---|---|
| Flutter | 3.47.1 |
| AotterTrek, Android | `trek-ads` 5.6.6 |
| AotterTrek, iOS | `AotterTrekSDK` 5.0.1 |
| iOS integration | Swift Package Manager; CocoaPods |

Release builds on Android need no R8 (ProGuard) rules from the app: the plugin
carries those the AotterTrek SDK needs.

## Example

`example/` shows native ads in a feed, in both built-in layouts and one of the
app's own, and a banner; see `example/README.md` to run it.
