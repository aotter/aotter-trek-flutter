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
  late int platformViewsCreated;

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      instanceManager.channel,
      (_) async => null,
    );
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
}
