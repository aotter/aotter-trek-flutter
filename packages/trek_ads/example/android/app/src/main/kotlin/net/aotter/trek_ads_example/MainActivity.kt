package net.aotter.trek_ads_example

import android.graphics.Color
import android.graphics.Typeface
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.TextView
import com.aotter.net.trek.ads.TrekNativeAdView
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import net.aotter.trek_ads.TrekAdsPlugin

// AotterTrek needs a FragmentActivity: impression tracking, players and the
// banner follow its lifecycle, and the interactive pop-up shows as a dialog in it.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A layout of the app's own for Native Ads (no media view), used by
        // TrekNativeAdWidget(factoryId: "example").
        TrekAdsPlugin.registerNativeAdFactory(flutterEngine, "example") { activity, ad, options ->
            val padding = (12 * activity.resources.displayMetrics.density).toInt()
            val cta = TextView(activity).apply {
                text = ad.callToAction.orEmpty()
                setTextColor(Color.parseColor("#1A73E8"))
                setTypeface(typeface, Typeface.BOLD)
            }
            val column = LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(padding, padding, padding, padding)
                setBackgroundColor(Color.parseColor("#FFF8E1"))
                addView(TextView(activity).apply { text = "${options?.get("label")} · ${ad.sponsor} · ${ad.advertiserName}" })
                addView(TextView(activity).apply {
                    text = ad.headline
                    textSize = 17f
                    setTextColor(Color.BLACK)
                })
                addView(TextView(activity).apply { text = ad.body })
                addView(cta)
            }
            TrekNativeAdView(activity).apply {
                // TrekNativeAdView is a ConstraintLayout: give the content the full width.
                addView(column, MATCH_PARENT, WRAP_CONTENT)
                setNativeAd(ad)
                // The whole ad clicks through, as on iOS.
                ad.setNativeAdClickAction(this)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        TrekAdsPlugin.unregisterNativeAdFactory(flutterEngine, "example")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
