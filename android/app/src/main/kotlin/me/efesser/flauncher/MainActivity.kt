/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package me.efesser.flauncher

import android.app.ActivityOptions
import android.content.Intent
import android.content.Intent.*
import android.content.pm.*
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.UserHandle
import android.util.Log
import android.view.KeyEvent
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.Serializable

private const val METHOD_CHANNEL = "me.efesser.flauncher/method"
private const val EVENT_CHANNEL = "me.efesser.flauncher/event"

class MainActivity : FlutterActivity() {
    val launcherAppsCallbacks = ArrayList<LauncherApps.Callback>()
    private var methodChannel: MethodChannel? = null

    // singleTask: a Home press while the launcher exists arrives here instead of starting a new activity.
    override fun onNewIntent(@NonNull intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ACTION_MAIN && intent.hasCategory(CATEGORY_HOME)) {
            methodChannel?.invokeMethod("homePressed", null)
        }
    }

    // A long press on Back opens the quick settings; a short press stays Back. Volume and mute keys never reach
    // apps on Google TV, and the Assistant button is owned by the voice service, so Back is the only spare
    // button. The key is consumed here, before Flutter, and a short press is replayed through onBackPressed()
    // on release so Flutter's route handling still sees it.
    private var backPressPending = false

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_BACK) {
            return super.dispatchKeyEvent(event)
        }
        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                if (event.repeatCount == 0) {
                    backPressPending = true
                } else if (backPressPending) {
                    backPressPending = false
                    methodChannel?.invokeMethod("quickSettingsPressed", null)
                }
            }
            KeyEvent.ACTION_UP -> {
                if (backPressPending) {
                    backPressPending = false
                    onBackPressed()
                }
            }
        }
        return true
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getApplications" -> result.success(getApplications())
                "applicationExists" -> result.success(applicationExists(call.arguments as String))
                "launchApp" -> result.success(launchApp(call.arguments as Map<*, *>))
                "openSystemSettings" -> result.success(openSystemSettings(call.arguments as String))
                "openAppInfo" -> result.success(openAppInfo(call.arguments as String))
                "uninstallApp" -> result.success(uninstallApp(call.arguments as String))
                "isDefaultLauncher" -> result.success(isDefaultLauncher())
                "checkForGetContentAvailability" -> result.success(checkForGetContentAvailability())
                "startAmbientMode" -> result.success(startAmbientMode())
                else -> throw IllegalArgumentException()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : StreamHandler {
            lateinit var launcherAppsCallback: LauncherApps.Callback
            val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
            override fun onListen(arguments: Any?, events: EventSink) {
                launcherAppsCallback = object : LauncherApps.Callback() {
                    override fun onPackageRemoved(packageName: String, user: UserHandle) {
                        events.success(mapOf("action" to "PACKAGE_REMOVED", "packageName" to packageName))
                    }

                    override fun onPackageAdded(packageName: String, user: UserHandle) {
                        getApplication(packageName)
                            ?.let { events.success(mapOf("action" to "PACKAGE_ADDED", "activitiyInfo" to it)) }
                    }

                    override fun onPackageChanged(packageName: String, user: UserHandle) {
                        getApplication(packageName)
                            ?.let { events.success(mapOf("action" to "PACKAGE_CHANGED", "activitiyInfo" to it)) }
                    }

                    override fun onPackagesAvailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {
                        val applications = packageNames.map(::getApplication)
                        if (applications.isNotEmpty()) {
                            events.success(mapOf("action" to "PACKAGES_AVAILABLE", "activitiesInfo" to applications))
                        }
                    }

                    override fun onPackagesUnavailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {}
                }

                launcherAppsCallbacks.add(launcherAppsCallback)
                launcherApps.registerCallback(launcherAppsCallback)
            }

            override fun onCancel(arguments: Any?) {
                launcherApps.unregisterCallback(launcherAppsCallback)
                launcherAppsCallbacks.remove(launcherAppsCallback)
            }
        })
    }

    override fun onDestroy() {
        val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
        launcherAppsCallbacks.forEach(launcherApps::unregisterCallback)
        super.onDestroy()
    }

    private fun getApplications(): List<Map<String, Serializable?>> {
        val tvActivitiesInfo = queryIntentActivities(false)
        val nonTvActivitiesInfo = queryIntentActivities(true)
                .filter { nonTvActivityInfo -> !tvActivitiesInfo.any { tvActivityInfo -> tvActivityInfo.packageName == nonTvActivityInfo.packageName } }
        return tvActivitiesInfo.map { buildAppMap(it, false) } + nonTvActivitiesInfo.map { buildAppMap(it, true) }
    }

    private fun getApplication(packageName: String): Map<String, Serializable?>? {
        if (packageName == this.packageName) return null
        return packageManager.getLeanbackLaunchIntentForPackage(packageName)
            ?.resolveActivityInfo(packageManager, 0)
            ?.let { buildAppMap(it, false) }
            ?: return packageManager.getLaunchIntentForPackage(packageName)
                ?.resolveActivityInfo(packageManager, 0)
                ?.let { buildAppMap(it, true) }
    }

    private fun applicationExists(packageName: String) = try {
        val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            PackageManager.MATCH_UNINSTALLED_PACKAGES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_UNINSTALLED_PACKAGES
        }
        packageManager.getApplicationInfo(packageName, flag)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun queryIntentActivities(sideloaded: Boolean) = packageManager
            .queryIntentActivities(Intent(ACTION_MAIN, null)
                    .addCategory(if (sideloaded) CATEGORY_LAUNCHER else CATEGORY_LEANBACK_LAUNCHER), 0)
            .map(ResolveInfo::activityInfo)
            .filter { it.packageName != packageName }

    private fun buildAppMap(activityInfo: ActivityInfo, sideloaded: Boolean) = mapOf(
            "name" to activityInfo.loadLabel(packageManager).toString(),
            "packageName" to activityInfo.packageName,
            "banner" to activityInfo.loadBanner(packageManager)?.let(::drawableToByteArray),
            "icon" to activityInfo.loadIcon(packageManager)?.let(::drawableToByteArray),
            "version" to packageManager.getPackageInfo(activityInfo.packageName, 0).versionName,
            "sideloaded" to sideloaded,
    )

    // The transition shapes how the app's window comes in: grown out of a rectangle of the launcher's window
    // (a tile or the band, in physical pixels), with no animation after the launcher played its own, or the
    // system default.
    private fun launchApp(arguments: Map<*, *>) = try {
        val packageName = arguments["packageName"] as String
        val intent = packageManager.getLeanbackLaunchIntentForPackage(packageName)
                ?: packageManager.getLaunchIntentForPackage(packageName)
        val source = (arguments["source"] as? List<*>)?.map { (it as Number).toInt() }
        val view = window.decorView
        val options = when (arguments["transition"]) {
            "reveal" -> source?.let { ActivityOptions.makeClipRevealAnimation(view, it[0], it[1], it[2], it[3]) }
            "scaleUp" -> source?.let { ActivityOptions.makeScaleUpAnimation(view, it[0], it[1], it[2], it[3]) }
            "fade" -> ActivityOptions.makeCustomAnimation(this, android.R.anim.fade_in, android.R.anim.fade_out)
            "none" -> {
                intent?.addFlags(FLAG_ACTIVITY_NO_ANIMATION)
                null
            }
            else -> null
        }
        startActivity(intent, options?.toBundle())
        true
    } catch (e: Exception) {
        Log.w("FLauncher", "launch failed: $e")
        false
    }

    // Deep links into the TV settings app. Each screen tries its intents in order; the generic settings root is
    // the last resort. Checked with `cmd package query-activities` on Google TV 14: WIFI_SETTINGS and
    // SOUND_SETTINGS resolve, BLUETOOTH_SETTINGS does not, and the settings slice for
    // "Remotes & accessories" opens the paired-devices list.
    private fun openSystemSettings(screen: String): Boolean {
        val accessoriesSlice = Intent("android.settings.SLICE_SETTINGS")
                .putExtra("slice_uri", "content://com.android.tv.settings.accessories.sliceprovider/general")
        val intents = when (screen) {
            "bluetooth" -> listOf(Intent(Settings.ACTION_BLUETOOTH_SETTINGS), accessoriesSlice)
            "wifi" -> listOf(Intent(Settings.ACTION_WIFI_SETTINGS))
            "displaySound" -> listOf(Intent(Settings.ACTION_SOUND_SETTINGS))
            else -> emptyList()
        } + Intent(Settings.ACTION_SETTINGS)
        for (intent in intents) {
            try {
                startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w("FLauncher", "settings intent ${intent.action} failed: $e")
            }
        }
        return false
    }

    private fun openAppInfo(packageName: String) = try {
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun uninstallApp(packageName: String) = try {
        Intent(ACTION_DELETE)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun checkForGetContentAvailability() = try {
        val intentActivities = packageManager.queryIntentActivities(Intent(ACTION_GET_CONTENT, null).setTypeAndNormalize("image/*"), 0)
        intentActivities.isNotEmpty()
    } catch (e: Exception) {
        false
    }

    private fun isDefaultLauncher() = try {
        val defaultLauncher = packageManager.resolveActivity(Intent(ACTION_MAIN).addCategory(CATEGORY_HOME), 0)
        defaultLauncher?.activityInfo?.packageName == packageName
    } catch (e: Exception) {
        false
    }

    private fun startAmbientMode() = try {
        Intent(ACTION_MAIN)
            .setClassName("com.android.systemui", "com.android.systemui.Somnambulator")
            .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray? {
        if (drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0) {
            return null
        }

        fun drawableToBitmap(drawable: Drawable): Bitmap {
            val bitmap = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            return bitmap
        }

        val bitmap = drawableToBitmap(drawable)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }
}
