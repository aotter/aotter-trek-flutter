package net.aotter.trek_gma_mediation

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class TrekGmaMediationPlugin : FlutterPlugin {
    private var engine: FlutterEngine? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        TrekAdSizeReporter.fallback = binding.binaryMessenger

        // Registered by the plugin, so apps write no native code.
        // GeneratedPluginRegistrant adds plugins in name order, so
        // google_mobile_ads is attached by now.
        @Suppress("DEPRECATION") // the only way to hand GoogleMobileAdsPlugin a factory from a plugin
        val engine = binding.flutterEngine
        this.engine = engine
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            engine, FACTORY_ID, TrekNativeAdFactory(binding.applicationContext, binding.binaryMessenger))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engine?.let { GoogleMobileAdsPlugin.unregisterNativeAdFactory(it, FACTORY_ID) }
        engine = null
        // The binding hands out the same messenger at attach and at detach.
        if (TrekAdSizeReporter.fallback === binding.binaryMessenger) TrekAdSizeReporter.fallback = null
    }

    private companion object {
        const val FACTORY_ID = "trek"
    }
}
