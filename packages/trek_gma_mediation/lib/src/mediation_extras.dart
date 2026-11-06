import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Per-request values for AotterTrek: the category, URL and title of the
/// content the ad appears in.
///
/// ```dart
/// AdRequest(
///   mediationExtras: TrekMediationExtras.of(
///     category: 'news',
///     contentUrl: 'https://example.com/article/1',
///     contentTitle: 'Article title',
///   ),
/// )
/// ```
///
/// Works the same with `AdManagerAdRequest`. To add other networks' extras,
/// spread this list into yours.
abstract final class TrekMediationExtras {
  // Android keys extras by adapter class, one per format and console; iOS has
  // a single adapter that reads any of these entries.
  static const List<String> _adapters = [
    'admobNative',
    'admobBanner',
    'gamNative',
    'gamBanner',
  ];

  static List<MediationExtras> of({
    String? category,
    String? contentUrl,
    String? contentTitle,
  }) {
    final values = <String, dynamic>{
      'Category': ?category,
      'ContentUrl': ?contentUrl,
      'ContentTitle': ?contentTitle,
    };
    return [
      for (final adapter in _adapters)
        _TrekExtras({...values, 'adapter': adapter}),
    ];
  }
}

class _TrekExtras implements MediationExtras {
  _TrekExtras(this._extras);

  final Map<String, dynamic> _extras;

  @override
  String getAndroidClassName() =>
      'net.aotter.trek_gma_mediation.TrekFlutterMediationExtras';

  @override
  String getIOSClassName() => 'TrekFlutterMediationExtras';

  @override
  Map<String, dynamic> getExtras() => _extras;
}
