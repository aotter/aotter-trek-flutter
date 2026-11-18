# google_mobile_ads instantiates mediation extras by class name.
-keep class net.aotter.trek_gma_mediation.TrekFlutterMediationExtras { *; }

# The rules below come with the AotterTrek SDK and adapters from 5.6.6 as well;
# they stay here until a release has been checked without them.

# trek-ads calls AotterTrek's servers through Retrofit. Under R8 full mode
# without these rules, R8 strips the generic signatures Retrofit reads, and
# every ad request fails at run time.
-keep,allowobfuscation,allowshrinking class retrofit2.Response
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation

# WorkManager, which play-services-ads brings in, creates its Room database by
# reflection. Room 2.2.5 keeps the database class but not its constructor, R8
# full mode removes it, and the app stops at start-up.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
