package net.aotter.trek_ads

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.aotter.net.dto.trek.response.TrekNativeAd
import com.aotter.net.trek.ads.TrekMediaView
import com.aotter.net.trek.ads.TrekNativeAdView
import kotlin.math.roundToInt

/**
 * The built-in layouts, picked by the ad's type: a Native Ad gets the icon row
 * (Android must not put a TrekMediaView in a Native Ad), a Native Multimedia Ad
 * the media card. [style] carries the Dart TrekNativeAdStyle as plain values.
 */
internal object TrekNativeAdLayouts : TrekNativeAdFactory {

    override fun createNativeAdView(activity: Activity, ad: TrekNativeAd, options: Map<*, *>?): TrekNativeAdView =
        Builder(activity, ad, options ?: emptyMap<String, Any>()).build()

    private class Builder(private val context: Context, private val ad: TrekNativeAd, private val style: Map<*, *>) {
        private val dp = context.resources.displayMetrics.density

        fun build(): TrekNativeAdView {
            val adView = TrekNativeAdView(context)
            (style["background"] as? Number)?.let { adView.setBackgroundColor(it.toInt()) }
            val cta = callToAction()
            val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
            var media: TrekMediaView? = null
            if (adTypeOf(ad.adType) == AdTypeMessage.NATIVE) {
                column.addView(header(iconSize = 48, end = cta), MATCH_PARENT, WRAP_CONTENT)
            } else {
                column.addView(header(iconSize = 40, end = null), MATCH_PARENT, WRAP_CONTENT)
                media = TrekMediaView(context)
                column.addView(AspectRatioFrame(context, aspectRatio()).apply { addView(media, MATCH_PARENT, MATCH_PARENT) },
                    MATCH_PARENT, WRAP_CONTENT)
                column.addView(footer(cta), MATCH_PARENT, WRAP_CONTENT)
            }
            adView.addView(column, MATCH_PARENT, WRAP_CONTENT)
            adView.setTrekMediaView(media)
            adView.setNativeAd(ad)
            // The whole ad clicks through, as on iOS; the call to action is a TextView, so its taps reach the ad view.
            ad.setNativeAdClickAction(adView)
            return adView
        }

        /** Width over height: the creative's own size, else the SDK's ratio (height over width), else 16:9. */
        private fun aspectRatio(): Float {
            if (ad.mediaWidth > 0 && ad.mediaHeight > 0) return ad.mediaWidth.toFloat() / ad.mediaHeight
            return ad.mediaContentAspectRatio?.takeIf { it > 0f }?.let { 1f / it } ?: (16f / 9f)
        }

        /** Icon, then sponsor + advertiser over the headline, then [end] if given. */
        private fun header(iconSize: Int, end: View?): View {
            val icon = ImageView(context).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
            rounded(icon)
            // The SDK downloads the icon with the ad. Without one the icon keeps its place,
            // so a layout's cards keep one shape.
            ad.imgIcon.drawable?.let(icon::setImageDrawable)
            val advertiserStyle = style["advertiser"] as? Map<*, *>
            // The sponsor label takes the advertiser's color; an ad without one gets an "Ad" badge.
            val sponsor = if (ad.sponsor.isEmpty()) adBadge() else text(ad.sponsor, 11f, Typeface.DEFAULT, null).apply {
                setTextColor((advertiserStyle?.get("textColor") as? Number)?.toInt() ?: Color.GRAY)
            }
            val advertiser = text(ad.advertiserName, 13f, Typeface.DEFAULT_BOLD, advertiserStyle)
            val headline = text(ad.headline, 15f, Typeface.DEFAULT_BOLD, style["headline"] as? Map<*, *>).apply { maxLines = 2 }

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
        private fun footer(cta: View): View {
            val body = text(ad.body, 13f, Typeface.DEFAULT, style["body"] as? Map<*, *>).apply { maxLines = 2 }
            return LinearLayout(context).apply {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(px(12), px(8), px(12), px(8))
                addView(body, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
                addView(cta, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = px(8) })
            }
        }

        private fun callToAction(): TextView {
            val ctaStyle = style["callToAction"] as? Map<*, *>
            return text(ad.callToAction, 13f, Typeface.DEFAULT_BOLD, ctaStyle).apply {
                gravity = Gravity.CENTER
                minWidth = px(64)
                setPadding(px(12), px(6), px(12), px(6))
                if (ctaStyle?.get("textColor") == null) setTextColor(Color.WHITE)
                background = GradientDrawable().apply {
                    setColor((ctaStyle?.get("backgroundColor") as? Number)?.toInt() ?: CTA_BLUE)
                    cornerRadius = (style["cornerRadius"] as? Number)?.toFloat()?.times(dp) ?: px(4).toFloat()
                }
            }
        }

        /** A green "Ad" badge, as Google's templates show one. */
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

        /** A TextView with a TrekNativeAdTextStyle applied over the given defaults. */
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

        /** cornerRadius rounds the icon and the call to action. */
        private fun rounded(view: View) {
            val radius = (style["cornerRadius"] as? Number)?.toFloat()?.times(dp) ?: return
            view.outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) =
                    outline.setRoundRect(0, 0, view.width, view.height, radius)
            }
            view.clipToOutline = true
        }

        private fun px(value: Int) = (value * dp).roundToInt()
    }

    /** Takes the width it is given and the height [ratio] (width over height) asks for. */
    private class AspectRatioFrame(context: Context, private val ratio: Float) : FrameLayout(context) {
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val height = (MeasureSpec.getSize(widthMeasureSpec) / ratio).roundToInt()
            super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
        }
    }

    private const val CTA_BLUE = 0xFF1A73E8.toInt()
    private const val AD_GREEN = 0xFF3A6728.toInt()
    private const val TEXT_GRAY = 0xFF555555.toInt() // UIColor.darkGray
}
