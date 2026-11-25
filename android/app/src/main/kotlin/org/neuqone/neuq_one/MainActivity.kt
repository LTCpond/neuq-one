package org.neuqone.neuq_one

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import io.flutter.plugin.common.MethodChannel
import java.net.URISyntaxException

class MainActivity : FlutterActivity() {
    private var cameraPermissionResult: MethodChannel.Result? = null
    private var photoPickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.neuqone.neuq_one/campus_card_camera"
        ).setMethodCallHandler { call, result ->
            val identifier = (call.arguments as? Number)?.toLong()
            val webView = identifier?.let {
                WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, it)
            }
            val page = webView?.url?.let(Uri::parse)
            val activeCardPage = page?.scheme == "https" &&
                page.host == "cardmobile.neuq.edu.cn" && page.userInfo == null &&
                (page.port == -1 || page.port == 443) && webView?.hasWindowFocus() == true
            when (call.method) {
                "requestCameraPermission" -> {
                    if (!activeCardPage || cameraPermissionResult != null) {
                        result.success(false)
                    } else if (checkSelfPermission(Manifest.permission.CAMERA) ==
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                    } else {
                        cameraPermissionResult = result
                        requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
                    }
                }
                "pickPhoto" -> {
                    if (activeCardPage && photoPickerResult == null) {
                        pickPhoto(result)
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.neuqone.neuq_one/campus_card_payment"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openWallet" -> {
                    val uri = (call.arguments as? String)?.let(Uri::parse)
                    val wallet = uri?.let { Wallet.forLink(it) }
                    result.success(uri != null && wallet != null && openWallet(uri, wallet))
                }
                "watchCashierFrames" -> {
                    (call.arguments as? Number)?.let {
                        watchCashierFrames(flutterEngine, it.toLong())
                    }
                    result.success(null)
                }
                "openWeChat" -> result.success(openWeChat())
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun pickPhoto(result: MethodChannel.Result) {
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .setType("image/*")
            .addCategory(Intent.CATEGORY_OPENABLE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        photoPickerResult = result
        try {
            startActivityForResult(picker, PHOTO_PICKER_REQUEST)
        } catch (_: ActivityNotFoundException) {
            photoPickerResult = null
            result.error("photo_picker_unavailable", null, null)
        }
    }

    @Deprecated("Uses the system activity result to return a photo URI to WebView.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PHOTO_PICKER_REQUEST) return
        val result = photoPickerResult
        photoPickerResult = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        val photo = try {
            uri?.takeIf { it.scheme == "content" &&
                contentResolver.getType(it)?.startsWith("image/") == true }
        } catch (_: SecurityException) {
            null
        }
        result?.success(photo?.toString())
    }

    private fun openWeChat(): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(Wallet.WECHAT.packageName) ?: return false
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            val result = cameraPermissionResult
            cameraPermissionResult = null
            result?.success(
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
        }
    }

    override fun onDestroy() {
        cameraPermissionResult?.success(false)
        cameraPermissionResult = null
        photoPickerResult?.success(null)
        photoPickerResult = null
        super.onDestroy()
    }

    companion object {
        private const val CAMERA_PERMISSION_REQUEST = 8104
        private const val PHOTO_PICKER_REQUEST = 8105
    }

    @Suppress("DEPRECATION")
    private fun watchCashierFrames(engine: FlutterEngine, identifier: Long) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val webView = WebViewFlutterAndroidExternalApi.getWebView(engine, identifier) ?: return
        webView.webViewClient = CashierFrameClient(webView.webViewClient, ::openFramedWallet)
    }

    private fun openFramedWallet(page: Uri, target: Uri): Boolean {
        val wallet = Wallet.forCashier(page) ?: return false
        val uri = if (target.scheme == "intent") {
            val intent = try {
                Intent.parseUri(target.toString(), Intent.URI_INTENT_SCHEME)
            } catch (_: URISyntaxException) {
                return false
            }
            if (intent.`package` != null && intent.`package` != wallet.packageName) return false
            intent.data ?: return false
        } else {
            target
        }
        if (Wallet.forLink(uri) != wallet) return false
        if (hasWindowFocus() && !openWallet(uri, wallet)) {
            Toast.makeText(this, "无法打开${wallet.label}，请确认已安装。", Toast.LENGTH_SHORT).show()
        }
        return true
    }

    private fun openWallet(uri: Uri, wallet: Wallet): Boolean {
        val checkout = Intent(Intent.ACTION_VIEW, uri)
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .setPackage(wallet.packageName)
        return try {
            startActivity(checkout)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private enum class Wallet(val label: String, val packageName: String) {
        WECHAT("微信", "com.tencent.mm"),
        ALIPAY("支付宝", "com.eg.android.AlipayGphone");

        companion object {
            fun forLink(uri: Uri): Wallet? {
                if (uri.fragment != null || uri.encodedQuery.isNullOrEmpty()) return null
                return when {
                    uri.scheme == "weixin" && uri.encodedAuthority == "wap" &&
                        uri.path == "/pay" -> WECHAT
                    uri.scheme == "alipays" && uri.encodedAuthority == "platformapi" &&
                        (uri.path == "/startapp" || uri.path == "/startApp") -> ALIPAY
                    else -> null
                }
            }

            fun forCashier(uri: Uri): Wallet? {
                if (uri.scheme != "https" || uri.userInfo != null ||
                    (uri.port != -1 && uri.port != 443)
                ) return null
                return when {
                    uri.host == "wx.tenpay.com" &&
                        uri.path == "/cgi-bin/mmpayweb-bin/checkmweb" -> WECHAT
                    uri.host == "mclient.alipay.com" -> ALIPAY
                    else -> null
                }
            }
        }
    }
}
