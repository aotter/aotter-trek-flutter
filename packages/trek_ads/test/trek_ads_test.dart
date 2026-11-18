import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek_ads/src/messages.g.dart';
import 'package:trek_ads/trek_ads.dart';

// The native side is stubbed on its Pigeon channels, so these tests cover the
// Dart side only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = TrekAdsHostApi.pigeonChannelCodec;
  const host = 'dev.flutter.pigeon.trek_ads.TrekAdsHostApi';

  /// What loadNativeAd answers, by call: an ad message or an error reply.
  late List<Object?> loadReplies;
  late List<List<Object?>> loadCalls;
  late int platformViewsCreated;
  late List<Map<Object?, Object?>> creationParams;
  late List<int> disposed;

  /// Notices for every AotterTrek ad on the page, and for this package's only.
  late int scrollNotices;
  late int ownNotices;
  late Set<SchedulerPhase> noticePhases;

  NativeAdMessage adMessage(
    String title, [
    AdTypeMessage adType = AdTypeMessage.nativeMultimedia,
  ]) => NativeAdMessage(
    title: title,
    body: 'body',
    callToAction: '',
    advertiserName: 'advertiser',
    sponsor: '',
    category: '',
    imageUrls: const [],
    adType: adType,
    isVideo: false,
    uuid: 'uuid',
    aspectRatio: 1200 / 628,
  );

  setUp(() {
    loadCalls = [];
    platformViewsCreated = 0;
    creationParams = [];
    disposed = [];
    scrollNotices = 0;
    ownNotices = 0;
    noticePhases = {};
    messenger.setMockMessageHandler('$host.notifyAdScrolled', (_) async {
      scrollNotices++;
      noticePhases.add(SchedulerBinding.instance.schedulerPhase);
      return codec.encodeMessage(<Object?>[null]);
    });
    messenger.setMockMessageHandler('$host.notifyOwnAdsScrolled', (_) async {
      ownNotices++;
      noticePhases.add(SchedulerBinding.instance.schedulerPhase);
      return codec.encodeMessage(<Object?>[null]);
    });
    messenger.setMockMessageHandler('$host.disposeAd', (message) async {
      disposed.add((codec.decodeMessage(message) as List<Object?>)[0]! as int);
      return codec.encodeMessage(<Object?>[null]);
    });
    for (final method in ['loadNativeAd', 'loadBannerAd', 'reloadBannerAd']) {
      messenger.setMockMessageHandler('$host.$method', (message) async {
        loadCalls.add(codec.decodeMessage(message) as List<Object?>);
        final reply = loadReplies.removeAt(0);
        return codec.encodeMessage(reply is List ? reply : <Object?>[reply]);
      });
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        platformViewsCreated++;
        final args = call.arguments as Map<Object?, Object?>;
        creationParams.add(
          const StandardMessageCodec().decodeMessage(
            ByteData.sublistView(args['params']! as Uint8List),
          ) as Map<Object?, Object?>,
        );
      }
      return null;
    });
  });

  /// Native calling Dart, as the SDK's events do.
  Future<void> fromNative(String method, List<Object?> args) =>
      messenger.handlePlatformMessage(
        'dev.flutter.pigeon.trek_ads.TrekAdsFlutterApi.$method',
        TrekAdsFlutterApi.pigeonChannelCodec.encodeMessage(args),
        (_) {},
      );

  int adIdOf(int call) => loadCalls[call][0]! as int;

  test(
    'load maps the ad and asks for custom clicks only with a handler',
    () async {
      loadReplies = [adMessage('a'), adMessage('b')];
      final plain = await TrekNativeAd.load('place');
      final custom = await TrekNativeAd.load(
        'place',
        listener: TrekNativeAdListener(onCustomClick: (_, _) {}),
      );

      expect(loadCalls[0][3], isFalse);
      expect(loadCalls[1][3], isTrue);
      expect(plain.title, 'a');
      expect(plain.adType, TrekAdType.nativeMultimedia);
      expect(plain.aspectRatio, closeTo(1.911, 0.001));
      expect(custom.title, 'b');
    },
  );

  test('load sends the request and maps the ad\'s type and size', () async {
    loadReplies = [
      NativeAdMessage(
        title: 'a',
        body: '',
        callToAction: '',
        advertiserName: '',
        sponsor: '',
        category: '',
        imageUrls: const [],
        adType: AdTypeMessage.native,
        isVideo: false,
        uuid: 'uuid',
        mediaWidth: 1200,
        mediaHeight: 628,
      ),
    ];
    final ad = await TrekNativeAd.load(
      'place',
      request: const TrekAdRequest(
        category: 'news',
        contentUrl: 'https://example.com/1',
        contentTitle: 'Title',
      ),
    );

    expect(loadCalls[0][1], 'place');
    final request = loadCalls[0][2]! as AdRequestMessage;
    expect(
      [request.category, request.contentUrl, request.contentTitle],
      ['news', 'https://example.com/1', 'Title'],
    );
    expect(ad.adType, TrekAdType.native);
    expect(ad.mediaSize, const Size(1200, 628));
  });

  test('every ad type maps to its own', () async {
    loadReplies = [
      for (final type in AdTypeMessage.values) adMessage(type.name, type),
    ];
    for (final type in AdTypeMessage.values) {
      expect((await TrekNativeAd.load('place')).adType.name, type.name);
    }
  });

  test('a failed load throws TrekAdError with the SDK code', () async {
    loadReplies = [
      ['load_failed', 'not initialized', 901],
    ];
    await expectLater(
      TrekNativeAd.load('place'),
      throwsA(
        isA<TrekAdError>()
            .having((e) => e.code, 'code', 901)
            .having((e) => e.message, 'message', 'not initialized'),
      ),
    );
  });

  test(
    'loadMany keeps the ads that loaded and fails only when all fail',
    () async {
      loadReplies = [
        adMessage('a'),
        ['load_failed', 'no ad', null],
        adMessage('c'),
      ];
      final ads = await TrekNativeAd.loadMany('place', count: 3);
      expect(ads.map((ad) => ad.title), ['a', 'c']);

      loadReplies = [
        ['load_failed', 'no ad', null],
        ['load_failed', 'no ad', null],
      ];
      await expectLater(
        TrekNativeAd.loadMany('place', count: 2),
        throwsA(isA<TrekAdError>()),
      );
      expect(() => TrekNativeAd.loadMany('place', count: 6), throwsRangeError);
    },
  );

  test('events reach the listener of the ad they name', () async {
    final seen = <String>[];
    loadReplies = [adMessage('a'), adMessage('b')];
    TrekNativeAdListener listener(String name) => TrekNativeAdListener(
      onImpression: (_) => seen.add('$name impression'),
      onClicked: (_) => seen.add('$name clicked'),
      onCustomClick: (_, url) => seen.add('$name custom $url'),
      onMediaLoaded: (_) => seen.add('$name media'),
      onFailedToShow: (_, e) => seen.add('$name failed ${e.code}'),
    );
    await TrekNativeAd.load('place', listener: listener('a'));
    final b = await TrekNativeAd.load('place', listener: listener('b'));

    await fromNative('onImpression', [adIdOf(1)]);
    await fromNative('onClicked', [adIdOf(0)]);
    await fromNative('onCustomClick', [adIdOf(1), 'https://x']);
    await fromNative('onMediaLoaded', [adIdOf(0)]);
    await fromNative('onFailedToShow', [adIdOf(1), 1101, 'player']);
    await b.dispose();
    await fromNative('onImpression', [adIdOf(1)]);

    expect(seen, [
      'b impression',
      'a clicked',
      'b custom https://x',
      'a media',
      'b failed 1101',
    ]);
  });

  test(
    'a banner reloads, gets its own events, and is disposed if it fails',
    () async {
      final seen = <String>[];
      loadReplies = [null, null];
      final banner = await TrekBannerAd.load(
        'banner',
        listener: TrekBannerAdListener(
          onImpression: (_) => seen.add('impression'),
          onClicked: (_) => seen.add('clicked'),
          onMediaLoaded: (_) => seen.add('media'),
        ),
      );
      await banner.reload();
      await fromNative('onMediaLoaded', [adIdOf(0)]);
      await fromNative('onImpression', [adIdOf(0)]);
      await fromNative('onClicked', [adIdOf(0)]);
      expect(adIdOf(1), adIdOf(0));
      expect(seen, ['media', 'impression', 'clicked']);

      loadReplies = [
        ['load_failed', 'no ad', null],
      ];
      await expectLater(banner.reload(), throwsA(isA<TrekAdError>()));

      loadReplies = [
        ['load_failed', 'no ad', null],
      ];
      await expectLater(
        TrekBannerAd.load(
          'banner',
          listener: TrekBannerAdListener(
            onImpression: (_) => seen.add('failed banner impression'),
          ),
        ),
        throwsA(isA<TrekAdError>()),
      );
      expect(disposed, [adIdOf(3)]);
      // Gone from Dart too: a late event for it reaches no listener.
      await fromNative('onImpression', [adIdOf(3)]);
      expect(seen, ['media', 'impression', 'clicked']);
    },
  );

  test(
    'a failed banner load is disposed whatever failed, and keeps its error',
    () async {
      // A failure that is not a TrekAdError, and a dispose that fails too.
      messenger.setMockMessageHandler('$host.loadBannerAd', (message) async {
        loadCalls.add(codec.decodeMessage(message) as List<Object?>);
        // Not a Pigeon reply: decoding it fails with a TypeError.
        return codec.encodeMessage('garbled');
      });
      messenger.setMockMessageHandler('$host.disposeAd', (message) async {
        disposed.add(
          (codec.decodeMessage(message) as List<Object?>)[0]! as int,
        );
        return codec.encodeMessage(<Object?>['dispose_failed', 'gone', null]);
      });

      await expectLater(TrekBannerAd.load('banner'), throwsA(isA<TypeError>()));
      expect(disposed, [adIdOf(0)]);
    },
  );

  test(
    'a listener that throws is reported, and native still gets a reply',
    () async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      loadReplies = [adMessage('a')];
      Never boom(Object _, [Object? _]) => throw StateError('boom');
      await TrekNativeAd.load(
        'place',
        listener: TrekNativeAdListener(
          onImpression: boom,
          onClicked: boom,
          onCustomClick: boom,
          onMediaLoaded: boom,
          onFailedToShow: boom,
        ),
      );

      final events = <String, List<Object?>>{
        'onImpression': [adIdOf(0)],
        'onClicked': [adIdOf(0)],
        'onCustomClick': [adIdOf(0), 'https://x'],
        'onMediaLoaded': [adIdOf(0)],
        'onFailedToShow': [adIdOf(0), 1101, 'player'],
      };
      for (final MapEntry(key: method, value: args) in events.entries) {
        final replied = Completer<ByteData?>();
        await messenger.handlePlatformMessage(
          'dev.flutter.pigeon.trek_ads.TrekAdsFlutterApi.$method',
          TrekAdsFlutterApi.pigeonChannelCodec.encodeMessage(args),
          replied.complete,
        );
        expect(
          TrekAdsFlutterApi.pigeonChannelCodec.decodeMessage(
            await replied.future,
          ),
          isEmpty,
          reason: method,
        );
      }

      expect(errors, hasLength(events.length));
      expect(errors.map((e) => e.exception), everyElement(isA<StateError>()));
    },
  );

  Widget host300(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 300, child: child)),
  );

  double heightOf(WidgetTester tester) =>
      tester.getSize(find.byType(TrekNativeAdWidget)).height;

  testWidgets('the widget takes the height the native layout reports', (
    tester,
  ) async {
    loadReplies = [adMessage('a')];
    final ad = await TrekNativeAd.load('place');
    await tester.pumpWidget(
      host300(TrekNativeAdWidget(ad: ad, initialHeight: 90)),
    );
    expect(heightOf(tester), 90);

    await fromNative('onAdHeight', [adIdOf(0), 123.0]);
    await tester.pump();
    expect(heightOf(tester), 123);

    // A list drops the row and builds it again: the height stays.
    await tester.pumpWidget(host300(const SizedBox()));
    await tester.pumpWidget(host300(TrekNativeAdWidget(ad: ad)));
    expect(heightOf(tester), 123);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a banner keeps a height that arrives before its load reply', (
    tester,
  ) async {
    // iOS reports the banner's size before it reports the ad.
    messenger.setMockMessageHandler('$host.loadBannerAd', (message) async {
      final args = codec.decodeMessage(message) as List<Object?>;
      loadCalls.add(args);
      await fromNative('onAdHeight', [args[0], 250.0]);
      return codec.encodeMessage(<Object?>[null]);
    });
    final banner = await TrekBannerAd.load('banner');
    await tester.pumpWidget(host300(TrekBannerAdWidget(ad: banner)));

    expect(tester.getSize(find.byType(TrekBannerAdWidget)).height, 250);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('the built-in layouts get the style, a factory its options', (
    tester,
  ) async {
    loadReplies = [adMessage('a'), adMessage('b')];
    final a = await TrekNativeAd.load('place');
    final b = await TrekNativeAd.load('place');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            SizedBox(
              width: 300,
              child: TrekNativeAdWidget(
                ad: a,
                style: const TrekNativeAdStyle(cornerRadius: 8),
              ),
            ),
            SizedBox(
              width: 300,
              child: TrekNativeAdWidget(
                ad: b,
                factoryId: 'mine',
                options: const {'label': 'x'},
              ),
            ),
          ],
        ),
      ),
    );

    expect(creationParams[0]['factoryId'], isNull);
    expect(creationParams[0]['options'], {'cornerRadius': 8.0});
    expect(creationParams[1]['factoryId'], 'mine');
    expect(creationParams[1]['options'], {'label': 'x'});
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  Widget scrollingList(List<Widget> ads, {ScrollPhysics? physics}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          physics: physics,
          children: [...ads, const SizedBox(height: 2000)],
        ),
      );

  testWidgets('on iOS, scrolling tells the ads once a frame', (tester) async {
    loadReplies = [adMessage('a'), adMessage('b'), adMessage('c')];
    final a = await TrekNativeAd.load('place');
    final b = await TrekNativeAd.load('place');
    final c = await TrekNativeAd.load('place');
    Widget feed({required bool automatic}) => scrollingList([
      for (final ad in [a, b, c])
        TrekNativeAdWidget(
          ad: ad,
          // Three ads above the drag's start, near the bottom of the screen.
          initialHeight: 150,
          notifyScrollAutomatically: automatic,
        ),
    ]);

    await tester.pumpWidget(feed(automatic: true));
    // Shown, the three were told once already, and only this package's ads.
    expect(ownNotices, 1);
    expect(scrollNotices, 0);
    var told = scrollNotices;
    final settled = await _drag(
      tester,
      onFrame: () {
        // Three ads, one notice for each frame that moved them.
        expect(scrollNotices - told, 1);
        told = scrollNotices;
      },
    );
    // And no more notices than frames while it settles.
    expect(scrollNotices - told, lessThanOrEqualTo(settled));
    // After the frame that moved them, not while the drag moves them.
    expect(noticePhases, {SchedulerPhase.postFrameCallbacks});

    scrollNotices = 0;
    await tester.pumpWidget(feed(automatic: false));
    await _drag(tester);
    expect(scrollNotices, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('on iOS, scrolling tells a banner too', (tester) async {
    loadReplies = [null];
    final banner = await TrekBannerAd.load('banner');
    await tester.pumpWidget(scrollingList([TrekBannerAdWidget(ad: banner)]));
    // The notice for showing the ad is not this test's.
    scrollNotices = 0;

    await _drag(tester);
    expect(scrollNotices, greaterThan(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'on iOS, ads are told when they are shown and when their media loads',
    (tester) async {
      loadReplies = [adMessage('a'), null];
      final ad = await TrekNativeAd.load('place');
      final banner = await TrekBannerAd.load('banner');
      await tester.pumpWidget(
        host300(
          Column(
            children: [
              TrekNativeAdWidget(ad: ad),
              TrekBannerAdWidget(ad: banner),
            ],
          ),
        ),
      );
      // Both shown in one frame: one notice, after that frame.
      expect(ownNotices, 1);
      expect(noticePhases, {SchedulerPhase.postFrameCallbacks});

      // No frame follows a creative's loading, so each is told at once.
      await fromNative('onMediaLoaded', [adIdOf(0)]);
      expect(ownNotices, 2);
      await fromNative('onMediaLoaded', [adIdOf(1)]);
      expect(ownNotices, 3);
      // Neither reaches the AotterTrek ads shown through AdMob.
      expect(scrollNotices, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'on iOS, a frame that scrolls tells every AotterTrek ad, though an ad was '
    'also shown in it',
    (tester) async {
      loadReplies = [adMessage('a'), adMessage('b'), adMessage('c')];
      final a = await TrekNativeAd.load('place');
      final b = await TrekNativeAd.load('place');
      final c = await TrekNativeAd.load('place');
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget feed(List<TrekNativeAd> ads) => Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          controller: controller,
          children: [
            for (final ad in ads)
              TrekNativeAdWidget(ad: ad, initialHeight: 150),
            const SizedBox(height: 2000),
          ],
        ),
      );
      await tester.pumpWidget(feed([a]));
      scrollNotices = 0;
      ownNotices = 0;

      // In one frame the list scrolls and a second ad is shown.
      controller.jumpTo(50);
      await tester.pumpWidget(feed([a, b]));
      expect(scrollNotices, 1);
      expect(ownNotices, 0);
      scrollNotices = 0;

      // The other way round: a third ad is shown, and the list scrolls before
      // the notice goes.
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => controller.jumpTo(100),
      );
      await tester.pumpWidget(feed([a, b, c]));
      expect(scrollNotices, 1);
      expect(ownNotices, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('on iOS, TrekAds.notifyAdScrolled tells every AotterTrek ad', (
    tester,
  ) async {
    await TrekAds.notifyAdScrolled();
    expect(scrollNotices, 1);
    expect(ownNotices, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'with the automatic notice off, showing an ad and its media tell nothing',
    (tester) async {
      loadReplies = [adMessage('a'), adMessage('b')];
      final ad = await TrekNativeAd.load('place');
      final other = await TrekNativeAd.load('place');
      await tester.pumpWidget(
        host300(TrekNativeAdWidget(ad: ad, notifyScrollAutomatically: false)),
      );
      await fromNative('onMediaLoaded', [adIdOf(0)]);
      await tester.pumpWidget(
        host300(
          TrekNativeAdWidget(ad: other, notifyScrollAutomatically: false),
        ),
      );
      expect(scrollNotices, 0);
      expect(ownNotices, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a widget given another ad waits for that ad\'s media', (
    tester,
  ) async {
    loadReplies = [adMessage('a'), adMessage('b')];
    final a = await TrekNativeAd.load('place');
    final b = await TrekNativeAd.load('place');
    await tester.pumpWidget(host300(TrekNativeAdWidget(ad: a)));
    expect(ownNotices, 1);
    // The same widget in the same place, now for the other ad: told as an ad
    // first shown is.
    await tester.pumpWidget(host300(TrekNativeAdWidget(ad: b)));
    expect(ownNotices, 2);
    // Built again for the same ad, nothing is told.
    await tester.pumpWidget(host300(TrekNativeAdWidget(ad: b)));
    expect(ownNotices, 2);
    ownNotices = 0;

    await fromNative('onMediaLoaded', [adIdOf(0)]);
    expect(ownNotices, 0);
    await fromNative('onMediaLoaded', [adIdOf(1)]);
    expect(ownNotices, 1);
    expect(scrollNotices, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('an ad no longer shown is not told when its media loads', (
    tester,
  ) async {
    loadReplies = [adMessage('a')];
    final ad = await TrekNativeAd.load('place');
    await tester.pumpWidget(host300(TrekNativeAdWidget(ad: ad)));
    await tester.pumpWidget(host300(const SizedBox()));
    ownNotices = 0;

    await fromNative('onMediaLoaded', [adIdOf(0)]);
    expect(ownNotices, 0);
    expect(scrollNotices, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('on Android, showing an ad and its media tell nothing', (
    tester,
  ) async {
    loadReplies = [adMessage('a'), adMessage('b')];
    final ad = await TrekNativeAd.load('place');
    final other = await TrekNativeAd.load('place');
    await tester.pumpWidget(host300(TrekNativeAdWidget(ad: ad)));
    await fromNative('onMediaLoaded', [adIdOf(0)]);
    await tester.pumpWidget(host300(TrekNativeAdWidget(ad: other)));
    expect(scrollNotices, 0);
    expect(ownNotices, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('an ad moved into a list by its key follows that list', (
    tester,
  ) async {
    loadReplies = [adMessage('a')];
    final ad = await TrekNativeAd.load('place');
    // The same widget, moved by its key: no didUpdateWidget.
    final widget = TrekNativeAdWidget(
      key: GlobalObjectKey(ad),
      ad: ad,
      initialHeight: 200,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [widget]),
      ),
    );
    await tester.pumpWidget(scrollingList([widget]));
    expect(platformViewsCreated, 1);
    // The notice for showing the ad is not this test's.
    scrollNotices = 0;

    await _drag(tester);
    expect(scrollNotices, greaterThan(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('an ad moved to another list stops following the first', (
    tester,
  ) async {
    loadReplies = [adMessage('a')];
    final ad = await TrekNativeAd.load('place');
    final widget = TrekNativeAdWidget(
      key: GlobalObjectKey(ad),
      ad: ad,
      initialHeight: 200,
    );
    // Two lists that both stay; the ad moves from the first to the second.
    Widget lists({required bool inFirst}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          for (final first in [true, false])
            Expanded(
              child: ListView(
                children: [
                  if (first == inFirst) widget,
                  const SizedBox(height: 2000),
                ],
              ),
            ),
        ],
      ),
    );
    await tester.pumpWidget(lists(inFirst: true));
    await tester.pumpWidget(lists(inFirst: false));
    expect(platformViewsCreated, 1);
    // The notice for showing the ad is not this test's.
    scrollNotices = 0;

    await _drag(tester, list: find.byType(Scrollable).first);
    expect(scrollNotices, 0);
    await _drag(tester, list: find.byType(Scrollable).last);
    expect(scrollNotices, greaterThan(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('an ad follows its list to a new scroll position', (
    tester,
  ) async {
    loadReplies = [adMessage('a')];
    final ad = await TrekNativeAd.load('place');
    // The same widget, so no didUpdateWidget: only its dependency on the
    // Scrollable tells it of the new position.
    final widget = TrekNativeAdWidget(ad: ad, initialHeight: 200);
    Widget feed(ScrollPhysics physics) =>
        scrollingList([widget], physics: physics);
    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    await tester.pumpWidget(feed(const ClampingScrollPhysics()));
    final first = position();
    // Another kind of physics gives the list a new ScrollPosition.
    await tester.pumpWidget(feed(const BouncingScrollPhysics()));
    expect(position(), isNot(same(first)));
    // The notice for showing the ad is not this test's.
    scrollNotices = 0;

    await _drag(tester);
    expect(scrollNotices, greaterThan(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('an ad taken off the list stops following it', (tester) async {
    loadReplies = [adMessage('a')];
    final ad = await TrekNativeAd.load('place');
    await tester.pumpWidget(
      scrollingList([TrekNativeAdWidget(ad: ad, initialHeight: 200)]),
    );
    await tester.pumpWidget(scrollingList([]));
    // The notice for showing the ad is not this test's.
    scrollNotices = 0;

    await _drag(tester);
    expect(scrollNotices, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a scroll notice nobody answers is no error', (tester) async {
    for (final method in ['notifyAdScrolled', 'notifyOwnAdsScrolled']) {
      messenger.setMockMessageHandler('$host.$method', (_) async => null);
    }
    loadReplies = [adMessage('a')];
    final ad = await TrekNativeAd.load('place');
    await tester.pumpWidget(
      scrollingList([TrekNativeAdWidget(ad: ad, initialHeight: 200)]),
    );

    await _drag(tester);
    await fromNative('onMediaLoaded', [adIdOf(0)]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('on Android, scrolling sends nothing', (tester) async {
    loadReplies = [adMessage('a')];
    final ad = await TrekNativeAd.load('place');
    await tester.pumpWidget(
      scrollingList([TrekNativeAdWidget(ad: ad, initialHeight: 200)]),
    );
    await _drag(tester);
    expect(scrollNotices, 0);
    expect(ownNotices, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('ads that trade places in an unkeyed list keep their views', (
    tester,
  ) async {
    loadReplies = [adMessage('a'), adMessage('b')];
    final a = await TrekNativeAd.load('place');
    final b = await TrekNativeAd.load('place');
    Widget feed(List<TrekNativeAd> ads) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          for (final ad in ads)
            SizedBox(width: 300, child: TrekNativeAdWidget(ad: ad)),
        ],
      ),
    );
    await tester.pumpWidget(feed([a, b]));
    await tester.pumpWidget(feed([b, a]));

    expect(tester.takeException(), isNull);
    expect(platformViewsCreated, 2);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('the app keying its own widget by the ad is no duplicate key', (
    tester,
  ) async {
    loadReplies = [adMessage('a')];
    final ad = await TrekNativeAd.load('place');
    await tester.pumpWidget(
      host300(
        KeyedSubtree(
          key: GlobalObjectKey(ad),
          child: TrekNativeAdWidget(ad: ad),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

/// Drags [list] (the only list by default) up in steps, a frame each, and
/// settles; [onFrame] runs after each of the drag's frames. Returns the frames
/// after the release.
Future<int> _drag(
  WidgetTester tester, {
  Finder? list,
  void Function()? onFrame,
}) async {
  final scrollable = list ?? find.byType(Scrollable);
  final position = tester.state<ScrollableState>(scrollable).position;
  final before = position.pixels;
  // Near the list's bottom, below the ads at its top.
  final gesture = await tester.startGesture(
    tester.getBottomLeft(scrollable) + const Offset(150, -50),
  );
  for (var i = 0; i < 5; i++) {
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    onFrame?.call();
  }
  await gesture.up();
  final settled = await tester.pumpAndSettle();
  // The list did scroll, so a count of none means something.
  expect(position.pixels, greaterThan(before));
  return settled;
}
