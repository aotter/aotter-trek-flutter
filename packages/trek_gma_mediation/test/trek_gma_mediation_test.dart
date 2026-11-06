import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:trek_gma_mediation/trek_gma_mediation.dart';

void main() {
  test('options pick the layout by unit type, each with its own size key', () {
    final a = TrekNativeAdOptions.forNativeMultimediaAdUnit();
    final b = TrekNativeAdOptions.forNativeMultimediaAdUnit();
    expect(a['trekLayout'], 'mediaCard');
    expect(TrekNativeAdOptions.forNativeAdUnit()['trekLayout'], 'iconRow');
    expect(TrekNativeAdOptions.sizeOnly().containsKey('trekLayout'), isFalse);
    expect(a['trekSizeKey'], isNot(b['trekSizeKey']));
    expect(a.containsKey('trekStyle'), isFalse);
  });

  test('Google template style is flattened and its templateType ignored', () {
    final options = TrekNativeAdOptions.forNativeAdUnit(
      style: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF112233),
        cornerRadius: 8,
        tertiaryTextStyle: NativeTemplateTextStyle(size: 12),
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFFFFFFF),
          backgroundColor: const Color(0xFF0000FF),
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
      ),
    );
    expect(options['trekLayout'], 'iconRow');
    expect(options['trekStyle'], {
      'background': 0xFF112233,
      'cornerRadius': 8.0,
      'body': {'size': 12.0},
      'callToAction': {
        'textColor': 0xFFFFFFFF,
        'backgroundColor': 0xFF0000FF,
        'size': 14.0,
        'fontStyle': 'bold',
      },
    });
  });

  test('extras reach every Trek adapter with only the given values', () {
    final extras = TrekMediationExtras.of(category: 'news', contentTitle: 'T');
    expect(extras.map((e) => e.getExtras()['adapter']), [
      'admobNative',
      'admobBanner',
      'gamNative',
      'gamBanner',
    ]);
    for (final e in extras) {
      expect(
        e.getAndroidClassName(),
        'net.aotter.trek_gma_mediation.TrekFlutterMediationExtras',
      );
      expect(e.getIOSClassName(), 'TrekFlutterMediationExtras');
      expect(e.getExtras()['Category'], 'news');
      expect(e.getExtras()['ContentTitle'], 'T');
      expect(e.getExtras().containsKey('ContentUrl'), isFalse);
    }
  });
}
