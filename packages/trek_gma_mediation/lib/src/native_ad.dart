import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Factory id of the built-in native ad layouts. The plugin registers it on
/// both platforms, so apps write no native code to use them.
const String trekNativeAdFactoryId = 'trek';

const String _sizeKey = 'trekSizeKey';

/// `customOptions` for a [NativeAd] shown in a [TrekMediationNativeAdWidget].
///
/// Pick the method that matches the ad unit's type: a Native Multimedia Ad
/// unit needs the media card, a Native Ad unit the icon row. The other way
/// round, the ad renders and is measured wrongly. An AotterTrek ad takes the
/// layout for its own type whatever the method; ads from other networks take
/// the method's.
///
/// Each call carries a fresh key that the native layout reports its height
/// under, so build new options for every ad.
abstract final class TrekNativeAdOptions {
  // Keys from before a hot restart never match a new one.
  static final int _seed = Random().nextInt(1 << 32);
  static int _next = 0;

  static String _key() => 'trek-$_seed-${_next++}';

  /// For Native Multimedia Ad units: icon, sponsor, advertiser and headline,
  /// then the creative at its own aspect ratio, then body and call to action.
  ///
  /// [style] is Google's template style, with its text styles mapped as in
  /// Google's Android templates (secondary is the advertiser, tertiary the
  /// body). Its `templateType` is ignored: this method picks the layout.
  static Map<String, Object> forNativeMultimediaAdUnit({
    NativeTemplateStyle? style,
  }) => _options('mediaCard', style);

  /// For Native Ad units: icon, sponsor, advertiser, headline and call to
  /// action in one row, with no media.
  ///
  /// [style] is Google's template style, with its text styles mapped as in
  /// Google's Android templates (secondary is the advertiser, tertiary the
  /// body). Its `templateType` is ignored: this method picks the layout.
  static Map<String, Object> forNativeAdUnit({NativeTemplateStyle? style}) =>
      _options('iconRow', style);

  /// Size reporting only, for an app's own `NativeAdFactory` that calls
  /// `TrekAdSizeReporter.attach` on its ad view. Merge with that factory's
  /// own options.
  static Map<String, Object> sizeOnly() => {_sizeKey: _key()};

  static Map<String, Object> _options(
    String layout,
    NativeTemplateStyle? style,
  ) => {
    'trekLayout': layout,
    if (style != null) 'trekStyle': _encodeStyle(style),
    _sizeKey: _key(),
  };

  // customOptions cross the platform channel, so only plain values go in.
  static Map<String, Object> _encodeStyle(NativeTemplateStyle style) => {
    'background': ?style.mainBackgroundColor?.toARGB32(),
    'cornerRadius': ?style.cornerRadius,
    for (final (name, text) in [
      ('headline', style.primaryTextStyle),
      ('advertiser', style.secondaryTextStyle),
      ('body', style.tertiaryTextStyle),
      ('callToAction', style.callToActionTextStyle),
    ])
      if (text != null)
        name: {
          'textColor': ?text.textColor?.toARGB32(),
          'backgroundColor': ?text.backgroundColor?.toARGB32(),
          'size': ?text.size,
          'fontStyle': ?text.style?.name,
        },
  };
}

/// Shows a loaded [NativeAd] in a box as tall as its native layout needs at
/// the available width, so the creative keeps its own aspect ratio (1.91:1,
/// 16:9 or 9:16) as in a native AotterTrek app.
///
/// The ad's `customOptions` must come from [TrekNativeAdOptions].
class TrekMediationNativeAdWidget extends StatelessWidget {
  const TrekMediationNativeAdWidget({
    super.key,
    required this.ad,
    this.initialHeight = 300,
  });

  /// A loaded ad, as for [AdWidget].
  final NativeAd ad;

  /// Height used until the native layout reports its own.
  final double initialHeight;

  @override
  Widget build(BuildContext context) {
    final key = ad.customOptions?[_sizeKey];
    assert(key != null, 'Build the NativeAd with TrekNativeAdOptions.');
    return ValueListenableBuilder<double?>(
      valueListenable: _ReportedHeights.of(key),
      builder: (_, height, child) =>
          SizedBox(height: height ?? initialHeight, child: child),
      // Keyed globally by the ad: a different ad gets its own platform view,
      // and an ad that moves to another row of an unkeyed list (a row
      // inserted above it) is moved along with its platform view.
      child: AdWidget(key: GlobalObjectKey(ad), ad: ad),
    );
  }
}

/// The heights the native layouts report, by ad key. They outlive the widgets,
/// so a widget built again for the same ad (a list row scrolled away and back)
/// starts at the right height: the native layout reports only changes.
// ponytail: one entry per ad for the life of the process; drop it when the ad
// is disposed if apps ever load ads by the thousands.
abstract final class _ReportedHeights {
  static const MethodChannel _channel = MethodChannel(
    'trek_gma_mediation/ad_size',
  );
  static final Map<Object?, ValueNotifier<double?>> _byKey = {};
  static bool _listening = false;

  static ValueNotifier<double?> of(Object? key) {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final height = (args['height'] as num?)?.toDouble();
        if (height != null && height > 0) _notifier(args['key']).value = height;
      });
    }
    return _notifier(key);
  }

  static ValueNotifier<double?> _notifier(Object? key) =>
      _byKey.putIfAbsent(key, () => ValueNotifier(null));
}
