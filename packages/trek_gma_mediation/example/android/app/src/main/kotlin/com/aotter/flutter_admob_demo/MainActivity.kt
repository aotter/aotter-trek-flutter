package com.aotter.flutter_admob_demo

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is a HARD requirement: the
// Trek Android SDK safe-casts to FragmentActivity in three places (banner
// refresh lifecycle, impression tracker pause/resume, and the CatRun popup's
// fragment manager) and silently degrades when the cast fails -- everything
// still looks normal on the surface, so a smoke test will not catch it.
class MainActivity : FlutterFragmentActivity()
