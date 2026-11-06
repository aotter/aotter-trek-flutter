package net.aotter.trek_gma_mediation

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewOutlineProvider
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.NativeAdFactory
import java.net.URL
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Tells TrekMediationNativeAdWidget (Dart) how tall an ad view's layout wants
 * to be at the width Flutter gives it, so the creative keeps its own aspect
 * ratio. Built-in layouts attach it themselves; an integrator's own
 * NativeAdFactory calls attach() with options from TrekNativeAdOptions.
 */
object TrekAdSizeReporter {
    // ponytail: one channel for the process; key it per engine if add-to-app needs several.
    internal var channel: MethodChannel? = null

    @JvmStatic
    fun attach(adView: View, customOptions: Map<String, Any>?) {
        val key = customOptions?.get("trekSizeKey") as? String ?: return
        var reported = 0
        adView.addOnLayoutChangeListener { v, left, _, right, _, _, _, _, _ ->
            val width = right - left
            if (width <= 0) return@addOnLayoutChangeListener
            // Measure after the pass, not inside it.
            v.post {
                v.measure(
                    View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                )
                val height = v.measuredHeight
                if (height <= 0 || abs(height - reported) <= 1) return@post
                reported = height
                channel?.invokeMethod(
                    "adSize",
                    mapOf("key" to key, "height" to height / v.resources.displayMetrics.density),
                )
                v.requestLayout()
            }
        }
    }
}

/**
 * The built-in layouts behind factory id "trek": "mediaCard" or "iconRow", picked
 * by an AotterTrek ad's own type (adapter extras, from 5.6.5), else by
 * customOptions["trekLayout"]. customOptions["trekStyle"] carries Google's
 * NativeTemplateStyle, flattened by TrekNativeAdOptions.
 *
 * Call to action shows exactly what the ad carries, blank when empty. So does the
 * sponsor label; an ad without one (other networks) gets Google's "Ad" badge, as
 * AdMob requires ad attribution.
 */
internal class TrekNativeAdFactory(private val context: Context) : NativeAdFactory {

    private val dp = context.resources.displayMetrics.density

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val style = customOptions?.get("trekStyle") as? Map<*, *> ?: emptyMap<String, Any>()
        val adView = NativeAdView(context)
        (style["background"] as? Number)?.let { adView.setBackgroundColor(it.toInt()) }
        val cta = callToAction(nativeAd, adView, style)
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        if (layoutFor(nativeAd, customOptions?.get("trekLayout") as? String ?: "mediaCard") == "iconRow") {
            column.addView(header(nativeAd, adView, style, iconSize = 48, end = cta), MATCH_PARENT, WRAP_CONTENT)
        } else {
            column.addView(header(nativeAd, adView, style, iconSize = 40, end = null), MATCH_PARENT, WRAP_CONTENT)
            // Weighted: while the platform view is still shorter than the layout, the column
            // shrinks the media instead of pushing the footer outside the ad view (GMA warns).
            column.addView(media(nativeAd, adView), LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
            column.addView(footer(nativeAd, adView, style, cta), MATCH_PARENT, WRAP_CONTENT)
        }
        adView.addView(column, MATCH_PARENT, WRAP_CONTENT)
        adView.setNativeAd(nativeAd)
        TrekAdSizeReporter.attach(adView, customOptions)
        return adView
    }

    /**
     * The layout for the AotterTrek placement's type, which the adapter puts in
     * the extras from 5.6.5; the app's choice for ads without it.
     */
    private fun layoutFor(ad: NativeAd, chosen: String): String {
        val adType = ad.extras.getString("adType")
        val layout = when (adType) {
            "NATIVE" -> "iconRow"
            "NATIVE_MULTIMEDIA", "BANNER" -> "mediaCard"
            else -> return chosen
        }
        if (layout != chosen) Log.w(TAG, "$adType ad shown as $layout, not the $chosen asked for")
        return layout
    }

    private fun media(ad: NativeAd, adView: NativeAdView): View {
        // The creative's own size (adapter extras), else mediaContent's ratio.
        val ratio = aspectRatio(ad)
        // Height follows width from the first measure: GMA flags a 0-high media view.
        // An exact height comes only from the column sharing out its space; take it.
        val media = object : MediaView(context) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.EXACTLY) {
                    return super.onMeasure(widthMeasureSpec, heightMeasureSpec)
                }
                val height = (MeasureSpec.getSize(widthMeasureSpec) / ratio).roundToInt()
                super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
            }
        }
        media.mediaContent = ad.mediaContent
        media.setImageScaleType(ImageView.ScaleType.FIT_CENTER)
        adView.mediaView = media
        return media
    }

    private fun aspectRatio(ad: NativeAd): Float {
        val w = ad.extras.getString("adSizeWidth")?.toFloatOrNull()
        val h = ad.extras.getString("adSizeHeight")?.toFloatOrNull()
        if (w != null && h != null && w > 0f && h > 0f) return w / h
        return ad.mediaContent?.aspectRatio?.takeIf { it > 0f } ?: (16f / 9f)
    }

    /** Icon, then sponsor + advertiser over the headline, then [end] if given. */
    private fun header(ad: NativeAd, adView: NativeAdView, style: Map<*, *>, iconSize: Int, end: View?): View {
        val icon = ImageView(context).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
        rounded(icon, style)
        // The icon keeps its place with nothing to show (the Trek adapter stands in a
        // blank bitmap when its download failed), so a layout's cards keep one shape.
        val drawable = ad.icon?.drawable
        val uri = ad.icon?.uri
        when {
            drawable != null -> icon.setImageDrawable(drawable)
            uri != null -> thread {
                val bitmap = runCatching {
                    URL(uri.toString()).openConnection()
                        .apply { connectTimeout = TIMEOUT_MS; readTimeout = TIMEOUT_MS }
                        .getInputStream().use(BitmapFactory::decodeStream)
                }.getOrNull()
                if (bitmap != null) icon.post { icon.setImageBitmap(bitmap) }
            }
        }
        val advertiserStyle = style["advertiser"] as? Map<*, *>
        // No GMA asset slot for the sponsor label; it takes the advertiser's color.
        val sponsorText = ad.extras.getString("Sponsor").orEmpty()
        val sponsor = if (sponsorText.isEmpty()) adBadge() else text(sponsorText, 11f, Typeface.DEFAULT, null).apply {
            setTextColor((advertiserStyle?.get("textColor") as? Number)?.toInt() ?: Color.GRAY)
        }
        val advertiser = text(ad.advertiser, 13f, Typeface.DEFAULT_BOLD, advertiserStyle)
        val headline = text(ad.headline, 15f, Typeface.DEFAULT_BOLD, style["headline"] as? Map<*, *>).apply { maxLines = 2 }
        adView.iconView = icon
        adView.advertiserView = advertiser
        adView.headlineView = headline

        val byline = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(sponsor, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginEnd = px(6) })
            addView(advertiser, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        }
        val texts = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(byline)
            addView(headline)
        }
        return LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(12), px(8), px(12), px(8))
            addView(icon, LinearLayout.LayoutParams(px(iconSize), px(iconSize)).apply { marginEnd = px(8) })
            addView(texts, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            end?.let { addView(it, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = px(8) }) }
        }
    }

    /** Body, then the call to action. */
    private fun footer(ad: NativeAd, adView: NativeAdView, style: Map<*, *>, cta: View): View {
        val body = text(ad.body, 13f, Typeface.DEFAULT, style["body"] as? Map<*, *>).apply { maxLines = 2 }
        adView.bodyView = body
        return LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(12), px(8), px(12), px(8))
            addView(body, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            addView(cta, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = px(8) })
        }
    }

    private fun callToAction(ad: NativeAd, adView: NativeAdView, style: Map<*, *>): TextView {
        val ctaStyle = style["callToAction"] as? Map<*, *>
        val cta = text(ad.callToAction, 13f, Typeface.DEFAULT_BOLD, ctaStyle).apply {
            gravity = Gravity.CENTER
            minWidth = px(64)
            setPadding(px(12), px(6), px(12), px(6))
            if (ctaStyle?.get("textColor") == null) setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                setColor((ctaStyle?.get("backgroundColor") as? Number)?.toInt() ?: CTA_BLUE)
                cornerRadius = (style["cornerRadius"] as? Number)?.toFloat()?.times(dp) ?: px(4).toFloat()
            }
        }
        adView.callToActionView = cta
        return cta
    }

    /** The "Ad" badge of Google's own templates (green, bold, 25x20). */
    private fun adBadge() = TextView(context).apply {
        text = "Ad"
        textSize = 10f
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        minWidth = px(25)
        minHeight = px(20)
        setPadding(px(4), 0, px(4), 0)
        setTextColor(AD_GREEN)
        background = GradientDrawable().apply {
            setStroke(px(1), AD_GREEN)
            cornerRadius = px(3).toFloat()
        }
    }

    /** A TextView with Google's NativeTemplateTextStyle applied over the given defaults. */
    private fun text(value: String?, size: Float, typeface: Typeface, style: Map<*, *>?) = TextView(context).apply {
        text = value.orEmpty()
        // One line, cut with an ellipsis, unless the caller allows more; as UILabel does on iOS.
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        textSize = (style?.get("size") as? Number)?.toFloat() ?: size
        this.typeface = when (style?.get("fontStyle")) {
            "normal" -> Typeface.DEFAULT
            "bold" -> Typeface.DEFAULT_BOLD
            "italic" -> Typeface.create(Typeface.DEFAULT, Typeface.ITALIC)
            "monospace" -> Typeface.MONOSPACE
            else -> typeface
        }
        // Fixed, not the context theme's, as on iOS: the theme must not decide whether ad text is readable.
        setTextColor((style?.get("textColor") as? Number)?.toInt() ?: TEXT_GRAY)
        (style?.get("backgroundColor") as? Number)?.let { setBackgroundColor(it.toInt()) }
    }

    /** Google's cornerRadius rounds the icon and the call to action. */
    private fun rounded(view: View, style: Map<*, *>) {
        val radius = (style["cornerRadius"] as? Number)?.toFloat()?.times(dp) ?: return
        view.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) =
                outline.setRoundRect(0, 0, view.width, view.height, radius)
        }
        view.clipToOutline = true
    }

    private fun px(value: Int) = (value * dp).roundToInt()

    private companion object {
        const val TAG = "TrekGmaMediation"
        const val CTA_BLUE = 0xFF1A73E8.toInt()
        const val AD_GREEN = 0xFF3A6728.toInt()
        const val TEXT_GRAY = 0xFF555555.toInt() // UIColor.darkGray
        const val TIMEOUT_MS = 10_000
    }
}
