package site.wingspot.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.suspendCancellableCoroutine
import site.wingspot.core.BoardingPass

private val OPTIONS = BarcodeScannerOptions.Builder()
    .setBarcodeFormats(Barcode.FORMAT_PDF417, Barcode.FORMAT_AZTEC, Barcode.FORMAT_QR_CODE, Barcode.FORMAT_DATA_MATRIX)
    .build()

/** The first barcode in [barcodes] whose text is a boarding pass. The name and booking code are skipped by the parser. */
private fun passIn(barcodes: List<Barcode>): BoardingPass? =
    barcodes.firstNotNullOfOrNull { b -> b.rawValue?.let { runCatching { BoardingPass.parse(it) }.getOrNull() } }

/** Reads a boarding pass from a picture the person picked. Null if there is none in it. Everything happens on the phone. */
suspend fun boardingPassInImage(context: Context, uri: android.net.Uri): BoardingPass? = try {
    val image = InputImage.fromFilePath(context, uri)
    val scanner = BarcodeScanning.getClient(OPTIONS)
    suspendCancellableCoroutine { cont ->
        scanner.process(image)
            .addOnSuccessListener { cont.resumeWith(Result.success(passIn(it))) }
            .addOnFailureListener { cont.resumeWith(Result.success(null)) }
            .addOnCompleteListener { scanner.close() }
    }
} catch (e: Exception) {
    null
}

/** A full-screen camera that reads the boarding pass barcode, with no picture taken or kept. */
@Composable
fun BoardingPassScanner(onPass: (BoardingPass) -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    var allowed by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var asked by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed = it; asked = true }
    if (!allowed) {
        Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.camera_needed), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.camera_why), style = MaterialTheme.typography.bodyMedium)
            if (asked) Text(stringResource(R.string.camera_denied), color = MaterialTheme.colorScheme.error)
            Button(onClick = { launcher.launch(Manifest.permission.CAMERA) }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.allow_camera)) }
            TextButton(onClick = onClose) { Text(stringResource(R.string.cancel)) }
        }
        return
    }
    val lifecycle = LocalLifecycleOwner.current
    val found = remember { AtomicBoolean(false) }
    val executor = remember { Executors.newSingleThreadExecutor() }
    val scanner = remember { BarcodeScanning.getClient(OPTIONS) }
    DisposableEffect(Unit) {
        onDispose { scanner.close(); executor.shutdown() }
    }
    Box(Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                val view = PreviewView(ctx)
                val future = ProcessCameraProvider.getInstance(ctx)
                future.addListener({
                    val provider = future.get()
                    val preview = Preview.Builder().build().also { it.surfaceProvider = view.surfaceProvider }
                    val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                    analysis.setAnalyzer(executor) { proxy ->
                        val media = proxy.image
                        if (media == null || found.get()) { proxy.close(); return@setAnalyzer }
                        scanner.process(InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees))
                            .addOnSuccessListener { barcodes ->
                                passIn(barcodes)?.let { pass -> if (found.compareAndSet(false, true)) view.post { onPass(pass) } }
                            }
                            .addOnCompleteListener { proxy.close() }
                    }
                    try {
                        provider.unbindAll()
                        provider.bindToLifecycle(lifecycle, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
                    } catch (e: Exception) {
                        // No camera: the person can close this and use a picture or type the flight.
                    }
                }, ContextCompat.getMainExecutor(ctx))
                view
            },
        )
        Column(Modifier.align(Alignment.BottomCenter).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.scan_aim), color = androidx.compose.ui.graphics.Color.White, style = MaterialTheme.typography.titleMedium)
            TextButton(onClick = onClose) { Text(stringResource(R.string.cancel), color = androidx.compose.ui.graphics.Color.White) }
        }
    }
}
