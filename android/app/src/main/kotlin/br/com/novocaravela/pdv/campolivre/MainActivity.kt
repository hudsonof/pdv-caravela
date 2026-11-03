package br.com.novocaravela.pdv.campolivre

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "br.com.novocaravela.pdv/stone_pos"
    private val returnScheme = "caravelapdv"
    private val scanRequestCode = 7310

    private var channel: MethodChannel? = null
    private var scanResult: MethodChannel.Result? = null
    private var pendingReturn: Map<String, Any?>? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "scanBarcode" -> launchScanner(result)
                "launchPayment" -> launchPayment(call.arguments as? Map<*, *>, result)
                "printBill" -> printBill(call.arguments as? Map<*, *>, result)
                "openManagement" -> openManagement(call.arguments as? Map<*, *>, result)
                "consumePendingReturn" -> {
                    val value = pendingReturn
                    pendingReturn = null
                    result.success(value)
                }
                else -> result.notImplemented()
            }
        }
        readStoneReturn(intent)
    }

    private fun launchScanner(result: MethodChannel.Result) {
        if (scanResult != null) {
            result.error("SCAN_BUSY", "A leitura já está em andamento.", null)
            return
        }
        scanResult = result
        try {
            startActivityForResult(
                Intent(this, ScannerActivity::class.java),
                scanRequestCode
            )
        } catch (error: Exception) {
            scanResult = null
            result.error("SCAN_UNAVAILABLE", error.message, null)
        }
    }

    private fun launchPayment(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val amount = (arguments?.get("amountCents") as? Number)?.toLong()
        if (amount == null || amount <= 0 || amount > 999999999L) {
            result.error("INVALID_AMOUNT", "O valor da conta é inválido para o app Stone.", null)
            return
        }
        val transactionType = when (arguments?.get("transactionType")?.toString()?.uppercase()) {
            "DEBIT" -> "debit"
            "CREDIT" -> "credit"
            "PIX" -> "PIX"
            else -> {
                result.error("INVALID_PAYMENT_TYPE", "Selecione débito, crédito ou Pix.", null)
                return
            }
        }

        val builder = Uri.Builder()
            .scheme("payment-app")
            .authority("pay")
            .appendQueryParameter("return_scheme", returnScheme)
            .appendQueryParameter("amount", amount.toString())
            .appendQueryParameter("editable_amount", "0")
            .appendQueryParameter("transaction_type", transactionType)

        val orderId = arguments?.get("orderId")?.toString()
        if (!orderId.isNullOrBlank()) {
            if (orderId.toLongOrNull() == null) {
                result.error(
                    "INVALID_ORDER_ID",
                    "O identificador Stone precisa ser numérico.",
                    null
                )
                return
            }
            builder.appendQueryParameter("order_id", orderId)
        }
        launchExternalIntent(builder.build(), result)
    }

    private fun printBill(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val content = arguments?.get("printableContent") as? List<*>
        if (content.isNullOrEmpty()) {
            result.error("EMPTY_PRINT", "A conta não possui conteúdo para impressão.", null)
            return
        }
        val json = JSONArray()
        content.forEach { item ->
            val row = item as? Map<*, *> ?: return@forEach
            val objectRow = JSONObject()
            row.forEach { (key, value) ->
                if (key != null && value != null) {
                    objectRow.put(key.toString(), value.toString())
                }
            }
            json.put(objectRow)
        }
        val builder = Uri.Builder()
            .scheme("printer-app")
            .authority("print")
            .appendQueryParameter("SHOW_FEEDBACK_SCREEN", "true")
            .appendQueryParameter("SCHEME_RETURN", returnScheme)
            .appendQueryParameter("PRINTABLE_CONTENT", json.toString())
        launchExternalIntent(builder.build(), result)
    }

    private fun openManagement(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val rawUrl = arguments?.get("url")?.toString()
        val uri = runCatching { Uri.parse(rawUrl) }.getOrNull()
        if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank()) {
            result.error("INVALID_MANAGEMENT_URL", "O endereço da gestão não é válido.", null)
            return
        }
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error("BROWSER_UNAVAILABLE", "Não há navegador disponível neste terminal.", null)
        } catch (error: Exception) {
            result.error("OPEN_URL_FAILED", error.message, null)
        }
    }

    private fun launchExternalIntent(uri: Uri, result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error(
                "STONE_APP_UNAVAILABLE",
                "O aplicativo Stone necessário não está instalado neste terminal.",
                null
            )
        } catch (error: Exception) {
            result.error("STONE_INTENT_FAILED", error.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != scanRequestCode) return
        val result = scanResult ?: return
        scanResult = null
        if (resultCode == RESULT_OK) {
            result.success(data?.getStringExtra(ScannerActivity.EXTRA_VALUE))
        } else if (data?.hasExtra("scan_error") == true) {
            result.error(
                "SCAN_FAILED",
                data.getStringExtra("scan_error") ?: "Não foi possível ler o código.",
                null
            )
        } else {
            result.success(null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readStoneReturn(intent)
    }

    private fun readStoneReturn(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != returnScheme) return
        val host = uri.host ?: return
        if (host != "pay-response" && host != "print") return

        val allowedKeys = if (host == "pay-response") {
            setOf(
                "code",
                "success",
                "reason",
                "message",
                "amount",
                "order_id",
                "itk",
                "atk",
                "type",
                "brand",
                "authorization_code"
            )
        } else {
            setOf("result", "status", "code", "message")
        }
        val values = mutableMapOf<String, String>()
        allowedKeys.forEach { key ->
            uri.getQueryParameter(key)?.let { values[key] = it }
        }
        val event = mapOf("host" to host, "values" to values)
        pendingReturn = event
        channel?.invokeMethod("stoneReturn", event)
    }
}
