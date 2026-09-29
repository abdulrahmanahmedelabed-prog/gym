package com.nadi.nadi_gym

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * إرسال SMS من شريحة الجوال مباشرة (التذكيرات الآلية بدون مزوّد مدفوع).
 * يطلب إذن SEND_SMS عند أول استخدام فقط.
 */
class MainActivity : FlutterActivity() {
    private class PendingSms(val phone: String, val text: String, val result: MethodChannel.Result)

    private var pending: PendingSms? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nadi/sms").setMethodCallHandler { call, result ->
            if (call.method != "send") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val phone = call.argument<String>("phone")
            val text = call.argument<String>("text") ?: ""
            if (phone.isNullOrBlank()) {
                result.error("ARG", "phone is required", null)
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < 23 || checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
                send(phone, text, result)
            } else {
                pending?.result?.error("BUSY", "another permission request is pending", null)
                pending = PendingSms(phone, text, result)
                requestPermissions(arrayOf(Manifest.permission.SEND_SMS), REQUEST_SMS)
            }
        }
    }

    private fun send(phone: String, text: String, result: MethodChannel.Result) {
        try {
            val sms: SmsManager = if (Build.VERSION.SDK_INT >= 31) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            // الرسائل العربية الطويلة تُقسّم تلقائياً (70 حرفاً لكل جزء)
            val parts = sms.divideMessage(text)
            sms.sendMultipartTextMessage(phone, null, parts, null, null)
            result.success(true)
        } catch (e: Exception) {
            result.error("SEND_FAILED", e.message ?: e.toString(), null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_SMS) return
        val p = pending ?: return
        pending = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            send(p.phone, p.text, p.result)
        } else {
            p.result.error("PERMISSION_DENIED", "SMS permission denied", null)
        }
    }

    companion object {
        private const val REQUEST_SMS = 4711
    }
}
