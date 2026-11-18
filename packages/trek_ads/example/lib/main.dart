import 'package:flutter/material.dart';
import 'package:trek_ads/trek_ads.dart';

// Pass with --dart-define-from-file; never commit real ids.
const clientId = String.fromEnvironment('TREK_CLIENT_ID');
const nativeAdPlace = String.fromEnvironment('NATIVE_AD_PLACE');
const nativeMultimediaAdPlace = String.fromEnvironment(
  'NATIVE_MULTIMEDIA_AD_PLACE',
);
const bannerPlace = String.fromEnvironment('BANNER_PLACE');

// Scrolls the feed to the end and back twice by itself, reloading the banner
// in between, for device runs nobody is holding.
const autoScroll = bool.fromEnvironment('AUTO_SCROLL');

void _log(String message) => debugPrint('[example] $message');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrekAds.setLogLevel(TrekLogLevel.normal);
  await TrekAds.initialize(clientId);
  _log('AotterTrek SDK ${await TrekAds.nativeSdkVersion}');
  runApp(const MaterialApp(home: FeedPage()));
}

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const int _rows = 30;
  static const int _adEvery = 6;

  final Map<int, TrekNativeAd> _ads = {};
  TrekBannerAd? _banner;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    for (var slot = 0; slot < _rows ~/ _adEvery; slot++) {
      _load(slot);
    }
    _loadBanner();
    if (autoScroll) _autoScroll();
  }

  Future<void> _autoScroll() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    for (var pass = 0; pass < 2; pass++) {
      if (pass == 1) await _reloadBanner();
      for (final toEnd in [true, false]) {
        _log('auto scroll ${toEnd ? 'down' : 'up'}');
        // Steps, so every ad gets a moment on screen; the extent grows as rows lay out.
        while (mounted &&
            (toEnd
                ? _scroll.offset < _scroll.position.maxScrollExtent
                : _scroll.offset > 0)) {
          await _scroll.animateTo(
            _scroll.offset + (toEnd ? 300 : -300),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    _log('auto scroll done');
  }

  Future<void> _loadBanner() async {
    try {
      final banner = await TrekBannerAd.load(
        bannerPlace,
        listener: TrekBannerAdListener(
          onImpression: (_) => _log('banner impression'),
          onClicked: (_) => _log('banner clicked'),
          onMediaLoaded: (_) => _log('banner media loaded'),
        ),
      );
      _log('banner loaded');
      if (!mounted) {
        await banner.dispose();
        return;
      }
      setState(() => _banner = banner);
    } on TrekAdError catch (e) {
      _log('banner failed: $e');
    }
  }

  Future<void> _reloadBanner() async {
    try {
      await _banner?.reload();
      _log('banner reloaded');
    } on TrekAdError catch (e) {
      _log('banner reload failed: $e');
    }
  }

  Future<void> _load(int slot) async {
    final place = slot.isEven ? nativeMultimediaAdPlace : nativeAdPlace;
    final name = 'feed/$slot';
    try {
      final ad = await TrekNativeAd.load(
        place,
        request: const TrekAdRequest(category: 'NEWS'),
        listener: TrekNativeAdListener(
          onImpression: (_) => _log('$name impression'),
          onClicked: (_) => _log('$name clicked'),
          onMediaLoaded: (_) => _log('$name media loaded'),
          onFailedToShow: (_, e) => _log('$name failed to show: $e'),
        ),
      );
      _log('$name loaded ${ad.adType.name} "${ad.title}"');
      if (!mounted) {
        await ad.dispose();
        return;
      }
      setState(() => _ads[slot] = ad);
    } on TrekAdError catch (e) {
      _log('$name failed: $e');
    }
  }

  @override
  void dispose() {
    for (final ad in _ads.values) {
      ad.dispose();
    }
    _banner?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AotterTrek ads'),
        actions: [
          IconButton(
            tooltip: 'Reload banner',
            onPressed: _banner == null ? null : _reloadBanner,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: _banner == null
          ? null
          : SafeArea(child: TrekBannerAdWidget(ad: _banner!)),
      body: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        itemCount: _rows,
        itemBuilder: (_, row) {
          final adRow = row % _adEvery == _adEvery - 1;
          final ad = adRow ? _ads[row ~/ _adEvery] : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ad != null
                // Slot 3 shows the app's own layout, registered in MainActivity (Android)
                // and AppDelegate (iOS).
                ? row ~/ _adEvery == 3
                      ? TrekNativeAdWidget(
                          ad: ad,
                          factoryId: 'example',
                          options: const {'label': 'Custom'},
                        )
                      : TrekNativeAdWidget(ad: ad)
                : adRow
                ? const SizedBox.shrink()
                : _Article(row),
          );
        },
      ),
    );
  }
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
