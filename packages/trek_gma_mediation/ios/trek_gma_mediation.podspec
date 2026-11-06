Pod::Spec.new do |s|
  s.name             = 'trek_gma_mediation'
  s.version          = '0.1.0'
  s.summary          = 'AotterTrek ads through Google Mobile Ads mediation for Flutter.'
  s.description      = <<-DESC
Brings the AotterTrek Google Mobile Ads adapter into a Flutter app and registers
native ad layouts that size themselves to each creative.
                       DESC
  s.homepage         = 'https://aotter.net'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Aotter' => 'service@aotter.net' }
  s.source           = { :path => '.' }
  s.source_files     = 'trek_gma_mediation/Sources/trek_gma_mediation/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'google_mobile_ads'
  # The AdMob / Ad Manager adapter; it brings AotterTrekSDK with it.
  s.dependency 'AotterTrekMediation', '~> 5.0', '>= 5.0.1'
  s.platform = :ios, '15.0'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
