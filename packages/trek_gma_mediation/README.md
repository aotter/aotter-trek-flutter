# trek_gma_mediation

[AotterTrek](https://aotter.net) ads in Flutter through Google Mobile Ads
mediation (AdMob and Ad Manager), on top of
[`google_mobile_ads`](https://pub.dev/packages/google_mobile_ads).

Depending on this package brings the AotterTrek adapters into the app
(`trek-admob-mediation` and `trek-gam-mediation` on Android,
`AotterTrekMediation` on iOS). Requests made with `google_mobile_ads` are then
filled by AotterTrek through the mediation groups set up in the AdMob or Ad
Manager console. The package also registers native ad layouts that size
themselves to each creative, so the app writes no native code.

The integration guide is at
[aotter.gitbook.io/flutter](https://aotter.gitbook.io/flutter).

## Requirements

- Flutter 3.44 or later and `google_mobile_ads` 9.2.0 or later.
- iOS 15 or later.
- Android `minSdk` 24. The app's `MainActivity` **must extend
  `FlutterFragmentActivity`**: the AotterTrek SDK depends on `FragmentActivity`
  and degrades silently without it.
- Android apps declare Aotter's Maven repository in their own Gradle
  configuration; repositories declared inside a plugin do not reach the app:

  ```kotlin
  maven { url = uri("https://deps.aotter.net/artifactory/libs-release-local") }
  ```

## Console setup

In the AdMob or Ad Manager console, add AotterTrek to each ad unit's mediation
group as a custom event. The class name and parameter differ by platform; see
AotterTrek's AdMob prerequisites for
[Android](https://aotter.gitbook.io/android/integration-of-third-party-ad-network/admob/prerequisites)
and [iOS](https://aotter.gitbook.io/ios/ios-1/admob/prerequisites).

## Native ads

Load a `NativeAd` with the built-in factory and show it in a
`TrekMediationNativeAdWidget`, which takes the height the native layout needs
at the available width:

```dart
final ad = NativeAd(
  adUnitId: '<your ad unit>',
  factoryId: trekNativeAdFactoryId,
  customOptions: TrekNativeAdOptions.forNativeMultimediaAdUnit(),
  request: const AdRequest(),
  listener: NativeAdListener(onAdLoaded: (_) => setState(() => loaded = true)),
)..load();

// Once loaded:
TrekMediationNativeAdWidget(ad: ad);
```

Match the options to the ad unit's type: `forNativeMultimediaAdUnit()` for
Native Multimedia Ad units, `forNativeAdUnit()` for Native Ad units. A Native
Ad unit in the multimedia layout renders and is measured wrongly. The
AotterTrek adapters name each ad's type, and the built-in layouts follow it,
logging a warning when it differs from the options; ads from other networks
take the options' layout.

Give the widget a width of at least 230 and let it pick its height; do not
wrap it in a fixed-height box.

Until the native layout reports its height, the widget is `initialHeight`
tall (300 by default). Set it close to what your ads need: while a layout is
taller than that, Google's native ad validator, shown in debug builds of test
ads, reports that "not all asset views lie inside the native ad view". Large
system font sizes and wide screens make the media card taller.

Both options take Google's `NativeTemplateStyle`. Its `templateType` is
ignored; the option picks the layout. The text styles map as in Google's
Android templates, and `cornerRadius` applies on both platforms (Google's
templates use it on iOS only):

| `NativeTemplateStyle` | Applies to |
|---|---|
| `mainBackgroundColor` | the ad's background |
| `cornerRadius` | the icon and the call to action |
| `primaryTextStyle` | the headline |
| `secondaryTextStyle` | the advertiser (the sponsor label takes its text color) |
| `tertiaryTextStyle` | the body |
| `callToActionTextStyle` | the call to action |

Google's iOS templates use the secondary style for the body and the tertiary
one for the advertiser, so swap those two when reusing an iOS template style.

Without a style, the headline, advertiser and body are dark gray and the ad's
background is transparent. On a dark page, set `mainBackgroundColor`: the green
"Ad" badge has no style of its own.

```dart
TrekNativeAdOptions.forNativeAdUnit(
  style: NativeTemplateStyle(
    templateType: TemplateType.small, // ignored
    mainBackgroundColor: Colors.white,
    cornerRadius: 8,
    callToActionTextStyle: NativeTemplateTextStyle(backgroundColor: Colors.teal),
  ),
)
```

An app with its own `NativeAdFactory` keeps the same sizing: merge
`TrekNativeAdOptions.sizeOnly()` into its `customOptions` and call
`TrekAdSizeReporter.attach(adView, customOptions)` on the view it returns.
On iOS, an AotterTrek Native Multimedia Ad takes its clicks from taps on the
`GADNativeAdView` and does not register its `callToActionView`. A button there
takes the tap for itself, so the tap does not reach the ad: turn off the
button's user interaction (`isUserInteractionEnabled = false`) or show the
call to action in a label.

## Request values

Pass the category, URL and title of the content the ad appears in:

```dart
AdRequest(
  mediationExtras: TrekMediationExtras.of(
    category: 'news',
    contentUrl: 'https://example.com/article/1',
    contentTitle: 'Article title',
  ),
)
```

## Banners

An AotterTrek banner placement has one size: 320 × 50, 320 × 100 or 300 × 250.
Request that size with `BannerAd`; the creative is not scaled to another size,
so do not use adaptive sizes. Refresh follows the AdMob or Ad Manager console.

## Callbacks and testing

- `onAdImpression` is Google Mobile Ads' callback and fires at a different time
  from AotterTrek's viewable impression; count impressions in AotterTrek's
  dashboard. On iOS, `onAdClicked` fires only for the first click on a native
  ad; a banner's fires for every click.
- On a registered test device, AdMob Network answers with test ads, so an
  AotterTrek custom event placed after it in the waterfall is not called. To
  see AotterTrek fill, use the Ad Inspector's single ad source test
  (`MobileAds.instance.openAdInspector`); it stays on across restarts until
  turned off there.

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
| Flutter | 3.47.1 (3.44 or later required) |
| `google_mobile_ads` | 9.2.0 |
| Google Mobile Ads SDK | iOS 13.11, Android 25.5 |
| AotterTrek, Android | `trek-admob-mediation` 5.6.5 (with `trek-ads` 5.6.5) |
| AotterTrek, iOS | `AotterTrekMediation` 5.0.1 (with `AotterTrekSDK` 5.0.1) |
| iOS integration | Swift Package Manager and CocoaPods |

- On iOS, Native Multimedia Ads with a parallax creative do not move with the
  page: the package does not yet call the AotterTrek SDK's `notifyAdScrolled`
  when the page scrolls.
- AotterTrekMediation for iOS supports Google Mobile Ads SDK 12 and 13. A
  `google_mobile_ads` release that requires SDK 14 cannot be resolved until
  AotterTrekMediation supports it.
- Ad Manager has not been tested on a device. It takes AotterTrek's Ad
  Manager adapter on Android (`trek-gam-mediation`, which the package brings
  in) and the same adapter as AdMob on iOS.
- `google_mobile_ads`' Next-Gen SDK mode on Android (`USE_NEXT_GEN_SDK=true`)
  is not supported: the AotterTrek adapters and the built-in layouts use the
  regular Google Mobile Ads SDK.

## Example

`example/` runs with Google's public test ad units by default; see
`example/README.md` to see AotterTrek fill.
