import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/net/aotter/trek_ads/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'net.aotter.trek_ads'),
    swiftOut: 'ios/trek_ads/Sources/trek_ads/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'trek_ads',
  ),
)
enum LogLevelMessage { none, normal, detail }

enum AdTypeMessage { native, nativeMultimedia, banner, unknown }

class UserMessage {
  String? email;
  String? phone;
  String? gender;
  String? birthday;
  String? fbId;
  String? firstPartyId;
}

class AdRequestMessage {
  String? category;
  String? contentUrl;
  String? contentTitle;
}

class NativeAdMessage {
  NativeAdMessage({
    required this.title,
    required this.body,
    required this.callToAction,
    required this.advertiserName,
    required this.sponsor,
    required this.category,
    required this.imageUrls,
    required this.adType,
    required this.isVideo,
    required this.uuid,
  });

  String title;
  String body;
  String callToAction;
  String advertiserName;
  String sponsor;
  String category;
  String? iconUrl;
  String? iconHdUrl;
  String? mainImageUrl;
  List<String> imageUrls;
  int? mediaWidth;
  int? mediaHeight;

  /// Width over height; null when the SDK gives none.
  double? aspectRatio;
  AdTypeMessage adType;
  bool isVideo;
  String uuid;
}

/// Dart calls into the native SDK. Ads are named by an id Dart picks before
/// the load, so every event names its ad.
@HostApi()
abstract class TrekAdsHostApi {
  void initialize(String clientId);
  void setLogLevel(LogLevelMessage level);
  void setUser(UserMessage user);
  String nativeSdkVersion();
  void notifyAdScrolled();

  /// The plugin's own ads only, not the other AotterTrek ads in the window.
  void notifyOwnAdsScrolled();

  /// Fails with a FlutterError whose details are the SDK's error code, if any.
  @async
  NativeAdMessage loadNativeAd(
    int adId,
    String placeUid,
    AdRequestMessage request,
    bool customClick,
  );
  bool isExpired(int adId);

  /// Loads a banner into a view the plugin keeps for [adId].
  @async
  void loadBannerAd(int adId, String placeUid, AdRequestMessage request);

  /// Loads the next ad into the banner. On failure the current ad stays.
  @async
  void reloadBannerAd(int adId);

  /// Native and banner ads alike.
  void disposeAd(int adId);
}

/// Native events, per ad.
@FlutterApi()
abstract class TrekAdsFlutterApi {
  void onImpression(int adId);
  void onClicked(int adId);
  void onCustomClick(int adId, String url);
  void onMediaLoaded(int adId);
  void onFailedToShow(int adId, int? code, String message);

  /// The height, in logical pixels, the ad's layout wants at its current width.
  void onAdHeight(int adId, double height);
}
