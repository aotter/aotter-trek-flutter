package net.aotter.trek_gma_mediation

import android.os.Bundle
import android.util.Pair
import com.aotter.trek.admob.mediation.ads.TrekAdmobCustomEventBanner
import com.aotter.trek.admob.mediation.ads.TrekAdmobCustomEventNative
import com.aotter.trek.gam.mediation.ads.TrekGamCustomEventBanner
import com.aotter.trek.gam.mediation.ads.TrekGamCustomEventNative
import com.google.android.gms.ads.mediation.MediationExtrasReceiver
import io.flutter.plugins.googlemobileads.FlutterMediationExtras

/**
 * The Android side of TrekMediationExtras (Dart). google_mobile_ads creates
 * one per entry by class name; each entry names the Trek adapter class its
 * bundle is keyed by, since the AdMob and Ad Manager adapters for native and
 * banner are separate classes.
 */
class TrekFlutterMediationExtras : FlutterMediationExtras() {
    private var values: Map<String, Any> = emptyMap()

    override fun setMediationExtras(extras: MutableMap<String, Any>) {
        super.setMediationExtras(extras)
        values = extras
    }

    override fun getMediationExtras(): Pair<Class<out MediationExtrasReceiver>, Bundle> {
        val bundle = Bundle()
        for (key in listOf("Category", "ContentUrl", "ContentTitle")) {
            (values[key] as? String)?.let { bundle.putString(key, it) }
        }
        val adapter: Class<out MediationExtrasReceiver> = when (values["adapter"]) {
            "admobBanner" -> TrekAdmobCustomEventBanner::class.java
            "gamNative" -> TrekGamCustomEventNative::class.java
            "gamBanner" -> TrekGamCustomEventBanner::class.java
            else -> TrekAdmobCustomEventNative::class.java
        }
        return Pair(adapter, bundle)
    }
}
