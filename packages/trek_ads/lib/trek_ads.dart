/// AotterTrek ads for Flutter, straight from the AotterTrek SDKs.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/messages.g.dart';

final TrekAdsHostApi _host = TrekAdsHostApi();

enum TrekLogLevel { none, normal, detail }

/// The app's user, for ad targeting. The SDK hashes email and phone itself.
class TrekUser {
  const TrekUser({
    this.email,
    this.phone,
    this.gender,
    this.birthday,
    this.fbId,
    this.firstPartyId,
  });

  final String? email;
  final String? phone;

  /// "M" or "F"; the SDKs send it as given.
  final String? gender;

  /// yyyy/MM/dd; the SDKs send it as given.
  final String? birthday;
  final String? fbId;
  final String? firstPartyId;
}

/// What the page around the ad is about.
class TrekAdRequest {
  const TrekAdRequest({this.category, this.contentUrl, this.contentTitle});

  final String? category;
  final String? contentUrl;
  final String? contentTitle;

  AdRequestMessage _message() => AdRequestMessage(
    category: category,
    contentUrl: contentUrl,
    contentTitle: contentTitle,
  );
}

enum TrekAdType { native, nativeMultimedia, banner, unknown }

/// A failed initialize, load or reload, or an ad that failed to show.
class TrekAdError implements Exception {
  const TrekAdError(this.message, {this.code});

  /// The SDK's error code, the same on both platforms: 800 (no ad), 900
  /// (server or other failure), 901 (not initialized) or 1000 (no placement).
  /// iOS has a few more, listed in the AotterTrek iOS SDK's README. Null when
  /// no SDK code applies, such as a failed initialize on Android, a reload
  /// that a newer one replaced, or reloading a disposed banner.
  final int? code;
  final String message;

  @override
  String toString() => 'TrekAdError(${code ?? '-'}): $message';
}

abstract final class TrekAds {
  /// Starts the SDK. Calling it again with another id switches to that id.
  static Future<void> initialize(String clientId) =>
      _host.initialize(clientId).catchError(_rethrowAsTrekError);

  static Future<void> setLogLevel(TrekLogLevel level) =>
      _host.setLogLevel(LogLevelMessage.values[level.index]);

  static Future<void> setUser(TrekUser user) => _host.setUser(
    UserMessage(
      email: user.email,
      phone: user.phone,
      gender: user.gender,
      birthday: user.birthday,
      fbId: user.fbId,
      firstPartyId: user.firstPartyId,
    ),
  );

  /// Does nothing: AotterTrek keeps the user once set, by design.
  static Future<void> removeUser() async {}

  /// Tells the ads where they are on the page, for creatives that move with
  /// it; on iOS the notice also reaches AotterTrek ads shown through AdMob or
  /// Ad Manager. Call it when [TrekNativeAdWidget.notifyScrollAutomatically]
  /// is off or an ad moves some other way than by its nearest [Scrollable].
  /// Android follows by itself; the call does nothing there.
  static Future<void> notifyAdScrolled() => _host.notifyAdScrolled();

  static Future<String> get nativeSdkVersion => _host.nativeSdkVersion();
}

Never _rethrowAsTrekError(Object error) {
  if (error is PlatformException) {
    throw TrekAdError(
      error.message ?? error.code,
      code: error.details is int ? error.details as int : null,
    );
  }
  throw error;
}

/// Events of one ad. Giving [onCustomClick] takes clicks over for ads that
/// allow it: the SDK counts the click and hands the landing URL over instead
/// of opening it. Links inside some creatives still open by themselves; the
/// README lists them.
class TrekNativeAdListener {
  const TrekNativeAdListener({
    this.onImpression,
    this.onClicked,
    this.onCustomClick,
    this.onMediaLoaded,
    this.onFailedToShow,
  });

  /// AotterTrek's viewable impression. On iOS, a video ad reports it again
  /// each time the video replays, by the SDK's design.
  final void Function(TrekNativeAd ad)? onImpression;
  final void Function(TrekNativeAd ad)? onClicked;
  final void Function(TrekNativeAd ad, String url)? onCustomClick;

  /// The ad's picture or creative finished loading in its media view; a
  /// layout without one does not get it.
  final void Function(TrekNativeAd ad)? onMediaLoaded;

  /// iOS only: an error after the ad was shown, such as 1101 for a creative
  /// the SDK cannot play.
  final void Function(TrekNativeAd ad, TrekAdError error)? onFailedToShow;
}

/// What native and banner ads share: an id the native side knows them by and
/// the height their native view reports.
abstract class _TrekAd {
  _TrekAd(this._id);

  // Picked before the load, so the native side files the ad under it.
  static int _nextId = 0;

  final int _id;
  final ValueNotifier<double?> _height = ValueNotifier(null);

  /// Counts the times the ad's media has loaded, for the widget showing it.
  final ValueNotifier<int> _mediaLoads = ValueNotifier(0);

  Future<void> dispose() {
    _Events.ads.remove(_id);
    return _host.disposeAd(_id);
  }

  void _onImpression();
  void _onClicked();
  void _onMediaLoaded();
}

/// A loaded native ad. Show it with [TrekNativeAdWidget], in one place at a
/// time, and [dispose] it when done.
class TrekNativeAd extends _TrekAd {
  TrekNativeAd._(super._id, NativeAdMessage m, this.listener)
    : title = m.title,
      body = m.body,
      callToAction = m.callToAction,
      advertiserName = m.advertiserName,
      sponsor = m.sponsor,
      category = m.category,
      iconUrl = m.iconUrl,
      iconHdUrl = m.iconHdUrl,
      mainImageUrl = m.mainImageUrl,
      imageUrls = m.imageUrls,
      mediaSize = m.mediaWidth != null && m.mediaHeight != null
          ? Size(m.mediaWidth!.toDouble(), m.mediaHeight!.toDouble())
          : null,
      aspectRatio = m.aspectRatio,
      adType = TrekAdType.values[m.adType.index],
      isVideo = m.isVideo,
      uuid = m.uuid;

  final TrekNativeAdListener listener;

  final String title;
  final String body;
  final String callToAction;
  final String advertiserName;
  final String sponsor;
  final String category;
  final String? iconUrl;
  final String? iconHdUrl;

  /// For reference only: an ad counts impressions only when shown through
  /// [TrekNativeAdWidget].
  final String? mainImageUrl;
  final List<String> imageUrls;

  /// The creative's size as each SDK reports it, which can differ between the
  /// platforms for the same ad.
  final Size? mediaSize;

  /// Width over height. For a Native Ad or Native Multimedia Ad without a
  /// size, Android fills in a default (16:9 for a video, 1200:628 otherwise);
  /// iOS gives null.
  final double? aspectRatio;

  /// [TrekAdType.unknown] for a type this version does not know.
  final TrekAdType adType;
  final bool isVideo;
  final String uuid;

  static Future<TrekNativeAd> load(
    String placeUid, {
    TrekAdRequest request = const TrekAdRequest(),
    TrekNativeAdListener listener = const TrekNativeAdListener(),
  }) async {
    _Events.listen();
    final id = _TrekAd._nextId++;
    final message = await _host
        .loadNativeAd(
          id,
          placeUid,
          request._message(),
          listener.onCustomClick != null,
        )
        .catchError(_rethrowAsTrekError);
    return _Events.ads[id] = TrekNativeAd._(id, message, listener);
  }

  /// Loads [count] (1 to 5) ads at once; fails only when every load does.
  static Future<List<TrekNativeAd>> loadMany(
    String placeUid, {
    required int count,
    TrekAdRequest request = const TrekAdRequest(),
    TrekNativeAdListener listener = const TrekNativeAdListener(),
  }) async {
    RangeError.checkValueInInterval(count, 1, 5, 'count');
    Object? firstError;
    final ads = await Future.wait([
      for (var i = 0; i < count; i++)
        load(
          placeUid,
          request: request,
          listener: listener,
        ).then<TrekNativeAd?>(
          (ad) => ad,
          onError: (Object e) {
            firstError ??= e;
            return null;
          },
        ),
    ]);
    final loaded = ads.nonNulls.toList();
    if (loaded.isEmpty) throw firstError!;
    return loaded;
  }

  Future<bool> isExpired() => _host.isExpired(_id);

  @override
  void _onImpression() => listener.onImpression?.call(this);

  @override
  void _onClicked() => listener.onClicked?.call(this);

  @override
  void _onMediaLoaded() => listener.onMediaLoaded?.call(this);
}

class TrekBannerAdListener {
  const TrekBannerAdListener({
    this.onImpression,
    this.onClicked,
    this.onMediaLoaded,
  });

  final void Function(TrekBannerAd ad)? onImpression;
  final void Function(TrekBannerAd ad)? onClicked;

  /// The creative finished loading, once per ad.
  final void Function(TrekBannerAd ad)? onMediaLoaded;
}

/// A banner placement. Its native view loads the ads: show it with
/// [TrekBannerAdWidget], [reload] it for the next ad, and [dispose] it when
/// done. The banner takes the size of each creative.
class TrekBannerAd extends _TrekAd {
  TrekBannerAd._(super._id, this.listener);

  final TrekBannerAdListener listener;

  static Future<TrekBannerAd> load(
    String placeUid, {
    TrekAdRequest request = const TrekAdRequest(),
    TrekBannerAdListener listener = const TrekBannerAdListener(),
  }) async {
    _Events.listen();
    final ad = TrekBannerAd._(_TrekAd._nextId++, listener);
    // Before the load returns: iOS reports the banner's size first.
    _Events.ads[ad._id] = ad;
    try {
      await _host
          .loadBannerAd(ad._id, placeUid, request._message())
          .catchError(_rethrowAsTrekError);
    } catch (_) {
      // The app needs the load's error, not one from the clean-up.
      await ad.dispose().catchError((Object _) {});
      rethrow;
    }
    return ad;
  }

  /// Shows the next ad; the current one stays when that fails.
  Future<void> reload() =>
      _host.reloadBannerAd(_id).catchError(_rethrowAsTrekError);

  @override
  void _onImpression() => listener.onImpression?.call(this);

  @override
  void _onClicked() => listener.onClicked?.call(this);

  @override
  void _onMediaLoaded() => listener.onMediaLoaded?.call(this);
}

class _Events implements TrekAdsFlutterApi {
  static final Map<int, _TrekAd> ads = {};
  static bool _listening = false;

  static void listen() {
    if (_listening) return;
    _listening = true;
    TrekAdsFlutterApi.setUp(_Events());
  }

  /// Runs an app's listener. What it throws is reported here: thrown back
  /// to the native side, it would end up nowhere.
  static void _call(void Function() listener) {
    try {
      listener();
    } catch (exception, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'trek_ads',
          context: ErrorDescription('while calling an ad listener'),
        ),
      );
    }
  }

  @override
  void onImpression(int adId) => _call(() => ads[adId]?._onImpression());

  @override
  void onClicked(int adId) => _call(() => ads[adId]?._onClicked());

  @override
  void onCustomClick(int adId, String url) => _call(() {
    if (ads[adId] case final TrekNativeAd ad) {
      ad.listener.onCustomClick?.call(ad, url);
    }
  });

  @override
  void onMediaLoaded(int adId) => _call(() {
    final ad = ads[adId];
    ad?._mediaLoads.value++;
    ad?._onMediaLoaded();
  });

  @override
  void onFailedToShow(int adId, int? code, String message) => _call(() {
    if (ads[adId] case final TrekNativeAd ad) {
      ad.listener.onFailedToShow?.call(ad, TrekAdError(message, code: code));
    }
  });

  @override
  void onAdHeight(int adId, double height) => ads[adId]?._height.value = height;
}

enum TrekNativeAdFontStyle { normal, bold, italic, monospace }

class TrekNativeAdTextStyle {
  const TrekNativeAdTextStyle({
    this.textColor,
    this.backgroundColor,
    this.size,
    this.fontStyle,
  });

  final Color? textColor;
  final Color? backgroundColor;
  final double? size;
  final TrekNativeAdFontStyle? fontStyle;

  Map<String, Object> _encode() => {
    'textColor': ?textColor?.toARGB32(),
    'backgroundColor': ?backgroundColor?.toARGB32(),
    'size': ?size,
    'fontStyle': ?fontStyle?.name,
  };
}

/// Colors and fonts of the built-in layouts. [cornerRadius] rounds the icon
/// and the call to action.
class TrekNativeAdStyle {
  const TrekNativeAdStyle({
    this.backgroundColor,
    this.cornerRadius,
    this.headline,
    this.advertiser,
    this.body,
    this.callToAction,
  });

  final Color? backgroundColor;
  final double? cornerRadius;
  final TrekNativeAdTextStyle? headline;
  final TrekNativeAdTextStyle? advertiser;
  final TrekNativeAdTextStyle? body;
  final TrekNativeAdTextStyle? callToAction;

  Map<String, Object> _encode() => {
    'background': ?backgroundColor?.toARGB32(),
    'cornerRadius': ?cornerRadius,
    'headline': ?headline?._encode(),
    'advertiser': ?advertiser?._encode(),
    'body': ?body?._encode(),
    'callToAction': ?callToAction?._encode(),
  };
}

/// Shows a [TrekNativeAd], drawn natively, in a box as tall as its layout
/// needs at the available width.
///
/// The built-in layouts give a Native Ad an icon row and a Native Multimedia
/// Ad a card with the creative at its own aspect ratio. For a layout of your
/// own, register a native ad factory in Kotlin and Swift
/// (`TrekAdsPlugin.registerNativeAdFactory`) and name it in [factoryId].
///
/// The native view is built once, when the ad is first shown: [style],
/// [factoryId] and [options] apply as they were then.
class TrekNativeAdWidget extends StatelessWidget {
  const TrekNativeAdWidget({
    super.key,
    required this.ad,
    this.style,
    this.factoryId,
    this.options,
    this.initialHeight = 300,
    this.notifyScrollAutomatically = true,
  }) : assert(
         factoryId != null || options == null,
         'options go to a factory of your own',
       );

  final TrekNativeAd ad;

  /// Colors and fonts of the built-in layouts.
  final TrekNativeAdStyle? style;

  /// A native ad factory registered by the app; null for the built-in layouts.
  final String? factoryId;

  /// Plain values handed to that factory.
  final Map<String, Object?>? options;

  /// Height used until the native layout reports its own.
  final double initialHeight;

  /// iOS only: tell creatives that move with the page where the ad is, when
  /// the widget is first built for it, when its media has loaded, and when
  /// the nearest [Scrollable] around the ad scrolls. When it is off, call
  /// [TrekAds.notifyAdScrolled] yourself: after
  /// [TrekNativeAdListener.onMediaLoaded], after the frame in which the ad is
  /// shown again somewhere else, and as the page scrolls. Notices from other
  /// widgets, banners and ads shown through AdMob or Ad Manager among them,
  /// can still reach this ad. Of the automatic notices, only those for
  /// scrolling also reach AotterTrek ads shown through AdMob or Ad Manager.
  final bool notifyScrollAutomatically;

  @override
  Widget build(BuildContext context) =>
      _AdView(ad, 'net.aotter.trek_ads/native', initialHeight, {
        'factoryId': ?factoryId,
        'options': ?(factoryId == null ? style?._encode() : options),
      }, followScroll: notifyScrollAutomatically);
}

/// Shows a [TrekBannerAd], as tall as its creative at the available width.
class TrekBannerAdWidget extends StatelessWidget {
  const TrekBannerAdWidget({
    super.key,
    required this.ad,
    this.initialHeight = 50,
  });

  final TrekBannerAd ad;

  /// Height used until the banner reports its own.
  final double initialHeight;

  @override
  Widget build(BuildContext context) => _AdView(
    ad,
    'net.aotter.trek_ads/banner',
    initialHeight,
    const {},
    followScroll: true,
  );
}

/// An ad's native view, as tall as it reports.
class _AdView extends StatefulWidget {
  const _AdView(
    this.ad,
    this.viewType,
    this.initialHeight,
    this.params, {
    required this.followScroll,
  });

  final _TrekAd ad;
  final String viewType;
  final double initialHeight;
  final Map<String, Object> params;
  final bool followScroll;

  @override
  State<_AdView> createState() => _AdViewState();
}

/// A key of the package's own type, so an app that keys its own widget with
/// `GlobalObjectKey(ad)` does not get a duplicate key.
class _AdKey extends GlobalObjectKey {
  const _AdKey(super.value);
}

class _AdViewState extends State<_AdView> {
  ScrollPosition? _position;

  /// iOS creatives that move with the page need telling, as a native app does
  /// from scrollViewDidScroll; Android follows by itself.
  bool get _tells =>
      widget.followScroll && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    widget.ad._mediaLoads.addListener(_mediaLoaded);
    // Shown at some place on the page without having scrolled there.
    if (_tells) _notifyAfterFrame(others: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(_AdView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ad != widget.ad) {
      oldWidget.ad._mediaLoads.removeListener(_mediaLoaded);
      widget.ad._mediaLoads.addListener(_mediaLoaded);
      // Another ad at this place, which it did not scroll to either.
      if (_tells) _notifyAfterFrame(others: false);
    }
    _follow();
  }

  /// Moved by a key, the same widget gets no didUpdateWidget, and no
  /// dependency tells it of a Scrollable it did not have before.
  @override
  void activate() {
    super.activate();
    _follow();
  }

  @override
  void dispose() {
    widget.ad._mediaLoads.removeListener(_mediaLoaded);
    _position?.removeListener(_scrolled);
    super.dispose();
  }

  /// A creative takes its place on the page from a notice, and can take it
  /// only once it has loaded: without this one, an ad on the first screen
  /// shows the picture for no place until the page scrolls.
  void _mediaLoaded() {
    // No frame may be coming, and nothing moved: told at once.
    if (_tells) _host.notifyOwnAdsScrolled().ignore();
  }

  // The nearest Scrollable only; an ad moved by an outer one needs
  // TrekAds.notifyAdScrolled.
  void _follow() {
    final position = _tells ? Scrollable.maybeOf(context)?.position : null;
    if (position == _position) return;
    _position?.removeListener(_scrolled);
    _position = position?..addListener(_scrolled);
  }

  static bool _notifyScheduled = false;
  static bool _notifyOthers = false;

  static void _scrolled() => _notifyAfterFrame(others: true);

  /// One call a frame, however many ads scrolled or were shown, after the
  /// frame that moved them. A scroll tells the other AotterTrek ads on the
  /// page too, such as those shown through AdMob; an ad shown tells only this
  /// package's ads: on iOS the SDK keeps the position an ad was told even if
  /// its creative could not take it yet, and an ad shown through AdMob, told
  /// that early, would miss the next notice for the same place.
  static void _notifyAfterFrame({required bool others}) {
    _notifyOthers |= others;
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      final tellOthers = _notifyOthers;
      _notifyOthers = false;
      // Nothing to do if no plugin answers, as in a test without one or after
      // the plugin detached from the engine.
      (tellOthers ? _host.notifyAdScrolled() : _host.notifyOwnAdsScrolled())
          .ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    return ValueListenableBuilder<double?>(
      valueListenable: ad._height,
      builder: (_, height, child) =>
          SizedBox(height: height ?? widget.initialHeight, child: child),
      // Keyed globally by the ad: an ad that moves to another row of an
      // unkeyed list keeps its platform view instead of getting a second one.
      child: KeyedSubtree(key: _AdKey(ad), child: _platformView()),
    );
  }

  Widget _platformView() {
    final viewType = widget.viewType;
    final params = {'adId': widget.ad._id, ...widget.params};
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    // Texture layer, falling back to hybrid composition for a view with a
    // SurfaceView (the video player), as google_mobile_ads does.
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (creation) =>
          PlatformViewsService.initSurfaceAndroidView(
              id: creation.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
            )
            ..addOnPlatformViewCreatedListener(creation.onPlatformViewCreated)
            ..create(),
    );
  }
}
