package net.aotter.trek_ads

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.FragmentActivity
import com.aotter.net.dto.User
import com.aotter.net.dto.trek.response.TrekNativeAd
import com.aotter.net.trek.TrekAds
import com.aotter.net.trek.TrekLogLevel
import com.aotter.net.trek.ads.CustomAdListener
import com.aotter.net.trek.ads.TrekAdError
import com.aotter.net.trek.ads.TrekAdListener
import com.aotter.net.trek.ads.TrekAdLoader
import com.aotter.net.trek.ads.TrekAdRequest
import com.aotter.net.trek.ads.TrekBannerAdView
import com.aotter.net.trek.ads.TrekNativeAdView
import com.aotter.net.utils.UserInfoUtils
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.abs

/**
 * Builds the view for an ad, for TrekNativeAdWidget(factoryId: ...). Return a
 * TrekNativeAdView with the ad bound: for a Native Multimedia Ad, call
 * setTrekMediaView before setNativeAd; never put a TrekMediaView in a Native
 * Ad; hand the views that click through to ad.setNativeAdClickAction (the
 * built-in layouts give it the whole TrekNativeAdView, as iOS clicks the whole
 * ad; a clickable view inside, such as a Button, keeps its taps unless it gets
 * the same call). TrekNativeAdView
 * is a ConstraintLayout: add your content with MATCH_PARENT width, or it
 * shrinks to fit. The plugin sizes the widget to the view and keeps the view
 * for the ad's lifetime.
 */
fun interface TrekNativeAdFactory {
    fun createNativeAdView(activity: Activity, ad: TrekNativeAd, options: Map<*, *>?): TrekNativeAdView
}

class TrekAdsPlugin : FlutterPlugin, ActivityAware, TrekAdsHostApi {
    private lateinit var appContext: Context
    private val factories = mutableMapOf<String, TrekNativeAdFactory>()
    private lateinit var events: TrekAdsFlutterApi
    private lateinit var scope: CoroutineScope
    private var activity: Activity? = null
    private val ads = mutableMapOf<Long, LoadedAd>()
    private val banners = mutableMapOf<Long, LoadedBanner>()

    /** A loaded ad and, once shown, the one view it is bound to; list recycling re-attaches that view. */
    private class LoadedAd(val ad: TrekNativeAd) {
        var view: TrekNativeAdView? = null
    }

    /** A banner view loads its own ads; [pending] is the load or reload Dart awaits. */
    private class LoadedBanner(val view: TrekBannerAdView, val request: TrekAdRequest) {
        var pending: CancellableContinuation<Unit>? = null

        fun settle(block: (CancellableContinuation<Unit>) -> Unit) {
            val pending = pending ?: return
            this.pending = null
            if (pending.isActive) block(pending)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        events = TrekAdsFlutterApi(binding.binaryMessenger)
        TrekAdsHostApi.setUp(binding.binaryMessenger, this)
        binding.platformViewRegistry.registerViewFactory(NATIVE_VIEW_TYPE, NativeAdViewFactory())
        binding.platformViewRegistry.registerViewFactory(BANNER_VIEW_TYPE, BannerViewFactory())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        TrekAdsHostApi.setUp(binding.binaryMessenger, null)
        (ads.keys + banners.keys).toList().forEach(::disposeAd)
        scope.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        // The SDK takes impression tracking, players and the banner's lifecycle from a
        // FragmentActivity, and quietly goes without them otherwise.
        if (binding.activity !is FragmentActivity) {
            Log.w(TAG, "${binding.activity.javaClass.name} is not a FragmentActivity: extend FlutterFragmentActivity")
        }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun initialize(clientId: String) {
        // The same keys as iOS reads from Info.plist, as <meta-data> in the app's manifest.
        val meta = appContext.packageManager
            .getApplicationInfo(appContext.packageName, PackageManager.GET_META_DATA).metaData
        fun key(name: String) = meta?.getString(name).orEmpty()
        try {
            TrekAds.initialize(
                context = appContext,
                clientId = clientId,
                OnInitializationCompleteListener = object : TrekAds.OnInitializationCompleteListener {
                    override fun onInitializationComplete() {}
                },
                ATSSPDomain = key("ATSSP-domain"),
                ATSSPPathFetchAd = key("ATSSP-path-fetchAd"),
                ATSSPEIDsAPIDomain = key("ATSSP-EIDsAPIDomain"),
                ATSSPPathEIDsAPIGenerate = key("ATSSP-path-EIDsAPIGenerate"),
                ATSSPPathEIDsAPIRefresh = key("ATSSP-path-EIDsAPIRefresh"),
                ATTrackerDomain = key("ATTracker-domain"),
                ATTrackerPathReport = key("ATTracker-path-report"),
            )
        } catch (e: Exception) {
            throw FlutterError("initialize_failed", e.message, null)
        }
    }

    override fun setLogLevel(level: LogLevelMessage) = TrekAds.setLogLevel(TrekLogLevel.valueOf(level.name))

    override fun setUser(user: UserMessage) = UserInfoUtils.setUserInfo(
        User(
            birthday = user.birthday.orEmpty(),
            email = user.email.orEmpty(),
            fbId = user.fbId.orEmpty(),
            gender = user.gender.orEmpty(),
            phone = user.phone.orEmpty(),
            fpId = user.firstPartyId.orEmpty(),
        )
    )

    override fun nativeSdkVersion(): String = TrekAds.getSdkVersion()

    // The SDK works out a creative's scroll position on every draw.
    override fun notifyAdScrolled() {}

    override fun notifyOwnAdsScrolled() {}

    override suspend fun loadNativeAd(
        adId: Long,
        placeUid: String,
        request: AdRequestMessage,
        customClick: Boolean,
    ): NativeAdMessage = suspendCancellableCoroutine { result ->
        // One loader per ad, so every event names its ad.
        val listener = if (customClick) CustomClickListener(adId, result) else AdListener(adId, result)
        TrekAdLoader.Builder(activity ?: appContext, placeUid)
            .withAdListener(listener)
            .build()
            .loadAd(request.toTrek())
    }

    override fun isExpired(adId: Long): Boolean = ads[adId]?.ad?.isExpired() ?: true

    override suspend fun loadBannerAd(adId: Long, placeUid: String, request: AdRequestMessage) {
        // Built with the Activity: the banner takes its lifecycle from a FragmentActivity.
        val activity = activity ?: throw FlutterError("load_failed", "No activity to show the banner in", null)
        val view = TrekBannerAdView(activity).apply {
            setPlaceUid(placeUid)
            setAdListener(BannerListener(adId))
        }
        val banner = LoadedBanner(view, request.toTrek())
        banners[adId] = banner
        reportHeight(view, adId)
        return loadBanner(banner)
    }

    override suspend fun reloadBannerAd(adId: Long) =
        loadBanner(banners[adId] ?: throw FlutterError("load_failed", "The banner was disposed", null))

    private suspend fun loadBanner(banner: LoadedBanner): Unit = suspendCancellableCoroutine { result ->
        banner.settle { it.resumeWithException(FlutterError("load_failed", "A newer load replaced this one", null)) }
        banner.pending = result
        banner.view.loadAd(banner.request)
    }

    override fun disposeAd(adId: Long) {
        val banner = banners.remove(adId)?.apply {
            settle { it.resumeWithException(FlutterError("load_failed", "The banner was disposed", null)) }
        }
        val view = ads.remove(adId)?.view ?: banner?.view ?: return
        (view.parent as? ViewGroup)?.removeView(view)
        when (view) {
            is TrekNativeAdView -> view.destroy()
            is TrekBannerAdView -> view.destroy()
        }
    }

    private fun send(event: suspend () -> Unit) {
        scope.launch { runCatching { event() } }
    }

    private open inner class AdListener(
        val adId: Long,
        private val result: CancellableContinuation<NativeAdMessage>,
    ) : TrekAdListener {
        override fun onAdLoaded(trekNativeAd: TrekNativeAd) {
            ads[adId] = LoadedAd(trekNativeAd)
            if (result.isActive) result.resume(trekNativeAd.toMessage())
        }

        override fun onAdFailedToLoad(error: TrekAdError) {
            if (result.isActive) result.resumeWithException(error.toFlutter())
        }

        override fun onAdMediaLoaded(trekNativeAd: TrekNativeAd) = send { events.onMediaLoaded(adId) }

        override fun onAdImpression() = send { events.onImpression(adId) }

        override fun onAdClicked() = send { events.onClicked(adId) }
    }

    /** Implementing CustomAdListener is what makes the SDK hand over the landing URL. */
    private inner class CustomClickListener(
        adId: Long,
        result: CancellableContinuation<NativeAdMessage>,
    ) : AdListener(adId, result), CustomAdListener {
        override fun onCustomClicked(url: String) = send { events.onCustomClick(adId, url) }
    }

    private inner class BannerListener(val adId: Long) : TrekAdListener {
        override fun onAdLoaded(trekNativeAd: TrekNativeAd) = settle { it.resume(Unit) }

        override fun onAdFailedToLoad(error: TrekAdError) = settle { it.resumeWithException(error.toFlutter()) }

        override fun onAdMediaLoaded(trekNativeAd: TrekNativeAd) = send { events.onMediaLoaded(adId) }

        override fun onAdImpression() = send { events.onImpression(adId) }

        override fun onAdClicked() = send { events.onClicked(adId) }

        private fun settle(block: (CancellableContinuation<Unit>) -> Unit) {
            banners[adId]?.settle(block)
        }
    }

    private inner class BannerViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val adId = ((args as Map<*, *>)["adId"] as Number).toLong()
            val view: View = banners[adId]?.view ?: View(context)
            (view.parent as? ViewGroup)?.removeView(view)
            return object : PlatformView {
                override fun getView() = view

                override fun dispose() {}
            }
        }
    }

    private inner class NativeAdViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val params = args as Map<*, *>
            val adId = (params["adId"] as Number).toLong()
            val loaded = ads[adId]
            // The SDK casts its view's context to FragmentActivity; the context handed
            // to a texture-layer platform view is a MutableContextWrapper.
            val activity = activity
            val factoryId = params["factoryId"] as? String
            val factory = if (factoryId == null) TrekNativeAdLayouts else factories[factoryId]
            if (factory == null) Log.e(TAG, "no native ad factory registered as \"$factoryId\"")
            val view: View = if (loaded == null || activity == null || factory == null) View(context) else {
                loaded.view ?: factory.createNativeAdView(activity, loaded.ad, params["options"] as? Map<*, *>)
                    .also {
                        loaded.view = it
                        reportHeight(it, adId)
                    }
            }
            (view.parent as? ViewGroup)?.removeView(view)
            return object : PlatformView {
                override fun getView() = view

                // The ad's view outlives its platform view; disposeAd destroys it.
                override fun dispose() {}
            }
        }
    }

    /** Tells Dart how tall the layout wants to be at the width Flutter gives it. */
    private fun reportHeight(view: View, adId: Long) {
        var reported = 0
        view.addOnLayoutChangeListener { v, left, _, right, _, _, _, _, _ ->
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
                send { events.onAdHeight(adId, height / v.resources.displayMetrics.density.toDouble()) }
                v.requestLayout()
            }
        }
    }

    companion object {
        private const val TAG = "TrekAds"
        private const val NATIVE_VIEW_TYPE = "net.aotter.trek_ads/native"
        private const val BANNER_VIEW_TYPE = "net.aotter.trek_ads/banner"

        /** Makes [factory] available to TrekNativeAdWidget(factoryId: [factoryId]) in [engine]. */
        @JvmStatic
        fun registerNativeAdFactory(engine: FlutterEngine, factoryId: String, factory: TrekNativeAdFactory) {
            plugin(engine).factories[factoryId] = factory
        }

        @JvmStatic
        fun unregisterNativeAdFactory(engine: FlutterEngine, factoryId: String) {
            plugin(engine).factories.remove(factoryId)
        }

        private fun plugin(engine: FlutterEngine) =
            engine.plugins.get(TrekAdsPlugin::class.java) as? TrekAdsPlugin
                ?: error("TrekAdsPlugin is not registered with this engine")
    }
}

private fun TrekNativeAd.toMessage(): NativeAdMessage {
    // Android gives height over width.
    val ratio = mediaContentAspectRatio?.takeIf { it > 0f }?.let { 1.0 / it }
    return NativeAdMessage(
        title = headline,
        body = body,
        callToAction = callToAction.orEmpty(),
        advertiserName = advertiserName,
        sponsor = sponsor,
        category = category,
        iconUrl = imgIcon.uri?.toString(),
        iconHdUrl = imgIconHd.uri?.toString(),
        // The SDK falls back to another picture itself, never to an icon.
        mainImageUrl = imgMain.uri?.toString(),
        imageUrls = images.map { it.src }.filter { it.isNotEmpty() },
        mediaWidth = mediaWidth.toLong().takeIf { it > 0 },
        mediaHeight = mediaHeight.toLong().takeIf { it > 0 },
        aspectRatio = ratio,
        adType = adTypeOf(adType),
        isVideo = isVideoAd(),
        uuid = uuid,
    )
}

private fun AdRequestMessage.toTrek(): TrekAdRequest = TrekAdRequest.Builder().apply {
    category?.let { setCategory(it) }
    contentUrl?.let { setContentUrl(it) }
    contentTitle?.let { setContentTitle(it) }
}.build()

// The codes match iOS's, which Dart reads from the details.
private fun TrekAdError.toFlutter() = FlutterError("load_failed", message, code.toLong())

internal fun adTypeOf(raw: String) = when (raw) {
    "NATIVE" -> AdTypeMessage.NATIVE
    "SUPR_AD", "NATIVE_MULTIMEDIA" -> AdTypeMessage.NATIVE_MULTIMEDIA
    "BANNER" -> AdTypeMessage.BANNER
    else -> AdTypeMessage.UNKNOWN
}
