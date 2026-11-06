package net.aotter.trek_gma_mediation

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class TrekGmaMediationPlugin : FlutterPlugin {
    private var engine: FlutterEngine? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        TrekAdSizeReporter.channel = MethodChannel(binding.binaryMessenger, "trek_gma_mediation/ad_size")

        // Registered by the plugin, so apps write no native code.
        // GeneratedPluginRegistrant adds plugins in name order, so
        // google_mobile_ads is attached by now.
        @Suppress("DEPRECATION") // the only way to hand GoogleMobileAdsPlugin a factory from a plugin
        val engine = binding.flutterEngine
        this.engine = engine
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            engine, FACTORY_ID, TrekNativeAdFactory(binding.applicationContext))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engine?.let { GoogleMobileAdsPlugin.unregisterNativeAdFactory(it, FACTORY_ID) }
        engine = null
    }

    private companion object {
        const val FACTORY_ID = "trek"
    }
}
