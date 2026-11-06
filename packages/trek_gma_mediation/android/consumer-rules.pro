# google_mobile_ads instantiates mediation extras by class name.
-keep class net.aotter.trek_gma_mediation.TrekFlutterMediationExtras { *; }

# OkHttp 4.8 (through trek-ads) references optional TLS providers that are
# not on the classpath; R8 fails release builds on them without these.
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
