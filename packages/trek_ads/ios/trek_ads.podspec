Pod::Spec.new do |s|
  s.name             = 'trek_ads'
  s.version          = '0.1.1'
  s.summary          = 'AotterTrek ads for Flutter, straight from the AotterTrek SDK.'
  s.description      = <<-DESC
Loads AotterTrek native and banner ads through the AotterTrek iOS SDK and shows
them as native views sized to each creative.
                       DESC
  s.homepage         = 'https://aotter.net'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Aotter' => 'service@aotter.net' }
  s.source           = { :path => '.' }
  s.source_files     = 'trek_ads/Sources/trek_ads/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'AotterTrekSDK', '~> 5.0', '>= 5.0.1'
  s.platform = :ios, '15.0'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
