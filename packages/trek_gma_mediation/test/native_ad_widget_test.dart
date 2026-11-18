import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart'
    show instanceManager;
import 'package:trek_gma_mediation/trek_gma_mediation.dart';

// AdWidget needs a loaded ad and a platform view; both channels are stubbed,
// so these tests cover the Dart side only.
void main() {
  const scroll = MethodChannel('trek_gma_mediation/scroll');
  late int platformViewsCreated;
  late int scrollNotices;
  late Set<SchedulerPhase> noticePhases;

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      instanceManager.channel,
      (_) async => null,
    );
    scrollNotices = 0;
    noticePhases = {};
    messenger.setMockMethodCallHandler(scroll, (call) async {
      if (call.method == 'notifyAdScrolled') {
        scrollNotices++;
        noticePhases.add(SchedulerBinding.instance.schedulerPhase);
      }
      return null;
    });
    platformViewsCreated = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') platformViewsCreated++;
      return null;
    });
  });

  NativeAd loadedAd() => NativeAd(
    adUnitId: 'unit',
    factoryId: trekNativeAdFactoryId,
    customOptions: TrekNativeAdOptions.forNativeAdUnit(),
    request: const AdRequest(),
    listener: NativeAdListener(),
  )..load();

  Widget host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 300, child: child)),
  );

  Future<void> report(WidgetTester tester, NativeAd ad, double height) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'trek_gma_mediation/ad_size',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('adSize', {
            'key': ad.customOptions!['trekSizeKey'],
            'height': height,
          }),
        ),
        (_) {},
      );

  double heightOf(WidgetTester tester) =>
      tester.getSize(find.byType(TrekMediationNativeAdWidget)).height;

  testWidgets('starts at initialHeight, then takes the reported height', (
    tester,
  ) async {
    final ad = loadedAd();
    await tester.pumpWidget(
      host(TrekMediationNativeAdWidget(ad: ad, initialHeight: 90)),
    );
    expect(heightOf(tester), 90);

    await report(tester, ad, 123);
    await tester.pump();
    expect(heightOf(tester), 123);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a widget built again for the same ad keeps its height', (
    tester,
  ) async {
    final ad = loadedAd();
    await tester.pumpWidget(host(TrekMediationNativeAdWidget(ad: ad)));
    await report(tester, ad, 77);
    await tester.pump();

    // A list drops the row and builds it again; the native layout does not
    // report again because its height did not change.
    await tester.pumpWidget(host(const SizedBox()));
    await tester.pumpWidget(host(TrekMediationNativeAdWidget(ad: ad)));
    expect(heightOf(tester), 77);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a different ad in the same place gets its own platform view', (
    tester,
  ) async {
    final a = loadedAd();
    final b = loadedAd();
    await tester.pumpWidget(host(TrekMediationNativeAdWidget(ad: a)));
    await tester.pump();
    await tester.pumpWidget(host(TrekMediationNativeAdWidget(ad: b)));
    await tester.pump();

    expect(platformViewsCreated, 2);
    expect(
      instanceManager.isWidgetAdIdMounted(instanceManager.adIdFor(a)!),
      isFalse,
    );
    expect(
      instanceManager.isWidgetAdIdMounted(instanceManager.adIdFor(b)!),
      isTrue,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'ads that trade places in an unkeyed list move with their views',
    (tester) async {
      final a = loadedAd();
      final b = loadedAd();
      Widget feed(List<NativeAd> ads) => Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            for (final ad in ads)
              SizedBox(width: 300, child: TrekMediationNativeAdWidget(ad: ad)),
          ],
        ),
      );
      await tester.pumpWidget(feed([a, b]));
      await tester.pump();
      await tester.pumpWidget(feed([b, a]));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(platformViewsCreated, 2);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('the app keying its own widget by the ad is no duplicate key', (
    tester,
  ) async {
    final ad = loadedAd();
    await tester.pumpWidget(
      host(
        KeyedSubtree(
          key: GlobalObjectKey(ad),
          child: TrekMediationNativeAdWidget(ad: ad),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  Widget scrollingList(List<Widget> ads, {ScrollPhysics? physics}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          physics: physics,
          children: [
            for (final ad in ads) SizedBox(width: 300, child: ad),
            const SizedBox(height: 2000),
          ],
        ),
      );

  testWidgets('on iOS, scrolling tells the ads once a frame', (tester) async {
    await tester.pumpWidget(
      scrollingList([
        TrekMediationNativeAdWidget(ad: loadedAd(), initialHeight: 200),
        TrekMediationNativeAdWidget(ad: loadedAd(), initialHeight: 200),
      ]),
    );

    var told = 0;
    final settled = await _drag(
      tester,
      onFrame: () {
        // Two ads, one notice for each frame that moved them.
        expect(scrollNotices - told, 1);
        told = scrollNotices;
      },
    );
    // And no more notices than frames while it settles.
    expect(scrollNotices - told, lessThanOrEqualTo(settled));
    // After the frame that moved them, not while the drag moves them.
    expect(noticePhases, {SchedulerPhase.postFrameCallbacks});
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('an ad follows its list to a new scroll position', (
    tester,
  ) async {
    // The same widget, so only its dependency on the Scrollable tells it of
    // the new position.
    final widget = TrekMediationNativeAdWidget(
      ad: loadedAd(),
      initialHeight: 200,
    );
    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    await tester.pumpWidget(
      scrollingList([widget], physics: const ClampingScrollPhysics()),
    );
    final first = position();
    // Another kind of physics gives the list a new ScrollPosition.
    await tester.pumpWidget(
      scrollingList([widget], physics: const BouncingScrollPhysics()),
    );
    expect(position(), isNot(same(first)));

    await _drag(tester);
    expect(scrollNotices, greaterThan(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('an ad moved into a list by its key follows that list', (
    tester,
  ) async {
    final ad = loadedAd();
    // The same widget, moved by its key.
    final widget = TrekMediationNativeAdWidget(
      key: GlobalObjectKey(ad),
      ad: ad,
      initialHeight: 200,
    );
    await tester.pumpWidget(host(Column(children: [widget])));
    await tester.pumpWidget(scrollingList([widget]));
    expect(platformViewsCreated, 1);

    await _drag(tester);
    expect(scrollNotices, greaterThan(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('an ad moved to another list stops following the first', (
    tester,
  ) async {
    final ad = loadedAd();
    final widget = TrekMediationNativeAdWidget(
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

    await _drag(tester, list: find.byType(Scrollable).first);
    expect(scrollNotices, 0);
    await _drag(tester, list: find.byType(Scrollable).last);
    expect(scrollNotices, greaterThan(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('an ad taken off the list stops following it', (tester) async {
    await tester.pumpWidget(
      scrollingList([
        TrekMediationNativeAdWidget(ad: loadedAd(), initialHeight: 200),
      ]),
    );
    await tester.pumpWidget(scrollingList([]));

    await _drag(tester);
    expect(scrollNotices, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a scroll notice nobody answers is no error', (tester) async {
    // No plugin: the channel gets no reply, as in an app's own widget test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(scroll.name, (_) async => null);
    await tester.pumpWidget(
      scrollingList([
        TrekMediationNativeAdWidget(ad: loadedAd(), initialHeight: 200),
      ]),
    );

    await _drag(tester);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('on Android, scrolling sends nothing', (tester) async {
    await tester.pumpWidget(
      scrollingList([
        TrekMediationNativeAdWidget(ad: loadedAd(), initialHeight: 200),
      ]),
    );

    await _drag(tester);
    expect(scrollNotices, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'the app tells the ads itself on iOS only',
    (tester) async {
      await TrekMediation.notifyAdScrolled();
      expect(
        scrollNotices,
        defaultTargetPlatform == TargetPlatform.iOS ? 1 : 0,
      );
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
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
