package com.raaste.raaste

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MAPS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openGoogleMapsDirections" -> {
                        val query = call.argument<String>("query")?.trim().orEmpty()
                        result.success(query.isNotEmpty() && openGoogleMapsDirections(query))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openGoogleMapsDirections(query: String): Boolean {
        val encodedQuery = Uri.encode(query)
        val directionsUri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$encodedQuery")
        val mapsIntent = Intent(Intent.ACTION_VIEW, directionsUri).apply {
            setPackage("com.google.android.apps.maps")
        }

        if (tryLaunch(mapsIntent)) return true

        val webIntent = Intent(Intent.ACTION_VIEW, directionsUri)
        return tryLaunch(webIntent)
    }

    private fun tryLaunch(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (error: Exception) {
            false
        }
    }

    companion object {
        private const val MAPS_CHANNEL = "raaste/maps"
    }
}
