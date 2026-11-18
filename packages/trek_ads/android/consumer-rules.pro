# trek-ads calls AotterTrek's servers through Retrofit. Under R8 full mode
# without these rules, R8 strips the generic signatures Retrofit reads, and
# every ad request fails at run time. trek-ads 5.6.6 carries the same two rules
# itself; they stay here until a release has been checked without them.
-keep,allowobfuscation,allowshrinking class retrofit2.Response
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation
