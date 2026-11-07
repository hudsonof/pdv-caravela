package br.com.novocaravela.pdv.campolivre

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.atomic.AtomicBoolean

class ScannerActivity : ComponentActivity() {
    companion object {
        const val EXTRA_VALUE = "scanned_value"
        private const val CAMERA_PERMISSION_REQUEST = 7320
    }

    private lateinit var previewView: PreviewView
    private lateinit var cameraProvider: ProcessCameraProvider
    private val finished = AtomicBoolean(false)
    private var barcodeScanner: BarcodeScanner? = null

    private fun scanner(): BarcodeScanner {
        barcodeScanner?.let { return it }
        val options = BarcodeScannerOptions.Builder()
            .setBarcodeFormats(
                Barcode.FORMAT_QR_CODE,
                Barcode.FORMAT_EAN_13,
                Barcode.FORMAT_EAN_8,
                Barcode.FORMAT_CODE_128,
                Barcode.FORMAT_CODE_39,
                Barcode.FORMAT_UPC_A
            )
            .build()
        return BarcodeScanning.getClient(options).also { barcodeScanner = it }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildScannerLayout()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            startCamera()
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST
            )
        }
    }

    private fun buildScannerLayout() {
        previewView = PreviewView(this).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(16, 20, 19))
            addView(
                previewView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )
        }

        val hint = TextView(this).apply {
            text = "Aponte para um QR Code ou código de barras"
            textSize = 17f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(18, 20, 18, 20)
            setBackgroundColor(0x99000000.toInt())
        }
        root.addView(
            hint,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        )

        val cancel = Button(this).apply {
            text = "Cancelar"
            setOnClickListener {
                finished.set(true)
                setResult(RESULT_CANCELED)
                finish()
            }
        }
        val cancelParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM
        ).apply {
            setMargins(20, 0, 20, 24)
        }
        root.addView(cancel, cancelParams)
        setContentView(root)
    }

    private fun startCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener(
            {
                try {
                    if (isFinishing || finished.get()) return@addListener
                    cameraProvider = providerFuture.get()
                    val preview = Preview.Builder().build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }
                    val analysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                    analysis.setAnalyzer(
                        ContextCompat.getMainExecutor(this),
                        ::analyzeFrame
                    )
                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(
                        this,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis
                    )
                } catch (_: Exception) {
                    finishWithError("Não foi possível iniciar a câmera deste terminal.")
                }
            },
            ContextCompat.getMainExecutor(this)
        )
    }

    private fun analyzeFrame(proxy: androidx.camera.core.ImageProxy) {
        if (finished.get()) {
            proxy.close()
            return
        }
        val mediaImage = proxy.image
        if (mediaImage == null) {
            proxy.close()
            return
        }
        val input = InputImage.fromMediaImage(
            mediaImage,
            proxy.imageInfo.rotationDegrees
        )
        scanner().process(input)
            .addOnSuccessListener { barcodes ->
                val value = barcodes.firstNotNullOfOrNull { barcode ->
                    barcode.rawValue?.trim()?.takeIf { it.isNotEmpty() }
                }
                if (value != null && finished.compareAndSet(false, true)) {
                    setResult(
                        RESULT_OK,
                        Intent().putExtra(EXTRA_VALUE, value)
                    )
                    finish()
                }
            }
            .addOnCompleteListener {
                proxy.close()
            }
    }

    private fun finishWithError(message: String) {
        if (finished.compareAndSet(false, true)) {
            setResult(RESULT_CANCELED, Intent().putExtra("scan_error", message))
            finish()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_PERMISSION_REQUEST) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            finishWithError("Permita o acesso à câmera para ler o código.")
        }
    }

    override fun onDestroy() {
        if (::cameraProvider.isInitialized) {
            cameraProvider.unbindAll()
        }
        barcodeScanner?.close()
        super.onDestroy()
    }
}
