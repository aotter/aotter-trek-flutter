import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:trek_gma_mediation/trek_gma_mediation.dart';

/// Example app for trek_gma_mediation: AotterTrek native ads in a feed, shown
/// in the built-in layouts, and a banner.
///
/// Google's public test units by default. To see AotterTrek fill, pass your own
/// units (mediation groups that include the AotterTrek custom event):
///   flutter run --dart-define-from-file=ad_units.local.json
/// with {"NATIVE_MULTIMEDIA_AD_UNIT": "...", "NATIVE_AD_UNIT": "...",
/// "BANNER_AD_UNIT": "..."}. ad_units.local.json is git-ignored. The AdMob app
/// ids come from android/local.properties (admob.appId) and
/// ios/Flutter/Local.xcconfig (GAD_APPLICATION_ID), both git-ignored; Google's
/// test apps otherwise.
final bool _iOS = defaultTargetPlatform == TargetPlatform.iOS;

String _unit(String defined, {required String android, required String ios}) =>
    defined.isNotEmpty ? defined : (_iOS ? ios : android);

// Google's native test unit stands in for both AotterTrek native unit types.
final String nativeMultimediaAdUnit = _unit(
  const String.fromEnvironment('NATIVE_MULTIMEDIA_AD_UNIT'),
  android: 'ca-app-pub-3940256099942544/2247696110',
  ios: 'ca-app-pub-3940256099942544/3986624511',
);
final String nativeAdUnit = _unit(
  const String.fromEnvironment('NATIVE_AD_UNIT'),
  android: 'ca-app-pub-3940256099942544/2247696110',
  ios: 'ca-app-pub-3940256099942544/3986624511',
);
final String bannerAdUnit = _unit(
  const String.fromEnvironment('BANNER_AD_UNIT'),
  android: 'ca-app-pub-3940256099942544/6300978111',
  ios: 'ca-app-pub-3940256099942544/2934735716',
);

// Tells AotterTrek what the ads appear next to.
final AdRequest _request = AdRequest(
  mediationExtras: TrekMediationExtras.of(
    category: 'example',
    contentUrl: 'https://example.com/feed',
    contentTitle: 'Example feed',
  ),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AotterTrek mediation example',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AotterTrek mediation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _open(context, 'Native ads in a feed', const FeedPage()),
          _open(context, 'Banner ad', const BannerPage()),
          OutlinedButton(
            onPressed: () => _openAdInspector(context),
            child: const Text('Ad Inspector'),
          ),
        ],
      ),
    );
  }

  // Google's Ad Inspector, where a single ad source test shows AotterTrek fill
  // on a test device. It opens on test devices only.
  void _openAdInspector(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    MobileAds.instance.openAdInspector((error) {
      if (error == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ad Inspector: ${error.message}')),
      );
    });
  }

  Widget _open(BuildContext context, String label, Widget page) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => page)),
        child: Text(label),
      ),
    );
  }
}

void _log(String name, String event) => debugPrint('[example] $name $event');

/// A feed with an ad in every sixth row, alternating a Native Multimedia Ad
/// unit and a Native Ad unit. The list builds rows lazily and drops those that
/// scroll away; each ad is loaded once and kept for the page's lifetime, so a
/// row that comes back shows the same ad again.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const int _rows = 30;
  static const int _adEvery = 6;

  final List<NativeAd> _ads = [];
  final Set<NativeAd> _loaded = {};

  @override
  void initState() {
    super.initState();
    for (var slot = 0; slot < _rows ~/ _adEvery; slot++) {
      _ads.add(_load(slot));
    }
  }

  NativeAd _load(int slot) {
    final multimedia = slot.isEven;
    final name = 'feed/$slot';
    return NativeAd(
      adUnitId: multimedia ? nativeMultimediaAdUnit : nativeAdUnit,
      factoryId: trekNativeAdFactoryId,
      // The layout must match the unit's type: a media card for a Native
      // Multimedia Ad unit, an icon row for a Native Ad unit.
      customOptions: multimedia
          ? TrekNativeAdOptions.forNativeMultimediaAdUnit(
              style: slot == 2 ? _style : null,
            )
          : TrekNativeAdOptions.forNativeAdUnit(),
      request: _request,
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          _log(name, 'loaded');
          if (mounted) setState(() => _loaded.add(ad as NativeAd));
        },
        // The page disposes every ad when it closes.
        onAdFailedToLoad: (_, error) => _log(name, 'failed: ${error.message}'),
        onAdImpression: (_) => _log(name, 'impression'),
        onAdClicked: (_) => _log(name, 'clicked'),
      ),
    )..load();
  }

  // Google's template style; its templateType is ignored, the options pick
  // the layout.
  static final NativeTemplateStyle _style = NativeTemplateStyle(
    templateType: TemplateType.medium,
    mainBackgroundColor: const Color(0xFFFFF8E1),
    cornerRadius: 8,
    primaryTextStyle: NativeTemplateTextStyle(
      textColor: const Color(0xFF0D47A1),
      style: NativeTemplateFontStyle.italic,
    ),
    callToActionTextStyle: NativeTemplateTextStyle(
      textColor: Colors.black,
      backgroundColor: const Color(0xFFFFB300),
    ),
  );

  @override
  void dispose() {
    for (final ad in _ads) {
      ad.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Native ads in a feed')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rows,
        itemBuilder: (_, row) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: row % _adEvery == _adEvery - 1
              ? _ad(_ads[row ~/ _adEvery])
              : _Article(row),
        ),
      ),
    );
  }

  Widget _ad(NativeAd ad) => _loaded.contains(ad)
      ? TrekMediationNativeAdWidget(ad: ad)
      : const SizedBox.shrink();
}

class _Article extends StatelessWidget {
  const _Article(this.row);

  final int row;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 120,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Article ${row + 1}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}

/// An AotterTrek banner placement has one size (320 × 50, 320 × 100 or
/// 300 × 250); request that size. The creative is not scaled to fit another.
const AdSize bannerSize = AdSize.banner;

class BannerPage extends StatefulWidget {
  const BannerPage({super.key});

  @override
  State<BannerPage> createState() => _BannerPageState();
}

class _BannerPageState extends State<BannerPage> {
  late final BannerAd _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _banner = BannerAd(
      adUnitId: bannerAdUnit,
      size: bannerSize,
      request: _request,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _log('banner', 'loaded');
          if (mounted) setState(() => _loaded = true);
        },
        // Also called when a refresh fails while the last banner is still
        // shown, so the banner is disposed only with the page.
        onAdFailedToLoad: (_, error) =>
            _log('banner', 'failed: ${error.message}'),
        onAdImpression: (_) => _log('banner', 'impression'),
        onAdClicked: (_) => _log('banner', 'clicked'),
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Banner ad')),
      body: Center(
        child: SizedBox(
          width: bannerSize.width.toDouble(),
          height: bannerSize.height.toDouble(),
          child: _loaded ? AdWidget(ad: _banner) : null,
        ),
      ),
    );
  }
}
