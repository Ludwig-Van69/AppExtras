package es.horasyvacaciones.horas_y_vacaciones

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Puente entre la app y el sistema de carpetas de Android (SAF).
 *
 * Solo accede a la carpeta o al archivo que el usuario elige con los
 * selectores del sistema: no hay permisos de almacenamiento generales.
 * Los errores llegan a Dart con un código: `no_access` (carpeta sin permiso o
 * borrada), `not_found`, `exists`, `busy` o `io`.
 */
class StorageBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private class Fail(val code: String, message: String) : Exception(message)

    private val channel = MethodChannel(messenger, CHANNEL)
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val resolver get() = activity.contentResolver

    /** Selector abierto a la espera de que el usuario elija. */
    private var pending: MethodChannel.Result? = null
    private var pendingCode = 0

    init {
        channel.setMethodCallHandler(this)
        // El CSV compartido no se queda en la caché: al abrir la app se
        // borran los de hace más de una hora (013, RF-19). La hora de margen
        // deja terminar a la app que lo esté leyendo.
        io.execute {
            val limit = System.currentTimeMillis() - 60 * 60 * 1000
            File(activity.cacheDir, "export").listFiles()
                ?.filter { it.lastModified() < limit }
                ?.forEach { it.delete() }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> launchPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                ),
                REQ_FOLDER, result,
            )
            "pickFile" -> launchPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*"),
                REQ_FILE, result,
            )
            "isAccessible" -> background(result) { isAccessible(arg(call, "folder")) }
            "writeFile" -> background(result) {
                writeFile(arg(call, "folder"), arg(call, "name"), bytes(call))
                null
            }
            "listFiles" -> background(result) {
                listFiles(arg(call, "folder")).map { it.second }
            }
            "readFile" -> background(result) {
                readFile(arg(call, "folder"), arg(call, "name"))
            }
            "deleteFile" -> background(result) {
                deleteFile(arg(call, "folder"), arg(call, "name"))
                null
            }
            "shareFile" -> background(result, onMain = true) {
                shareFile(arg(call, "name"), arg(call, "mime"), bytes(call))
                null
            }
            else -> result.notImplemented()
        }
    }

    // ---- Selectores del sistema -------------------------------------------

    private fun launchPicker(intent: Intent, code: Int, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Ya hay un selector abierto", null)
            return
        }
        pending = result
        pendingCode = code
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, code)
        } catch (e: Exception) {
            pending = null
            result.error("io", "No se pudo abrir el selector", null)
        }
    }

    /** Devuelve true si el resultado era de uno de nuestros selectores. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val result = pending
        if (result == null || requestCode != pendingCode) return false
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // El usuario canceló.
            return true
        }
        if (requestCode == REQ_FOLDER) {
            try {
                resolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                result.success(uri.toString())
            } catch (e: Exception) {
                result.error("no_access", "No se pudo guardar el permiso", null)
            }
        } else {
            background(result) { copyToCache(uri) }
        }
        return true
    }

    /** Copia el archivo elegido a la caché de la app y devuelve su ruta. */
    private fun copyToCache(uri: Uri): String {
        val dir = File(activity.cacheDir, "picked").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val out = File(dir, "elegido.db")
        try {
            resolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: throw Fail("not_found", "No se pudo abrir el archivo")
        } catch (e: Fail) {
            throw e
        } catch (e: Exception) {
            throw Fail("io", "No se pudo leer el archivo")
        }
        return out.absolutePath
    }

    // ---- Carpeta ----------------------------------------------------------

    private fun tree(folder: String): Uri = Uri.parse(folder)

    private fun parentUri(folder: String): Uri {
        val tree = tree(folder)
        return DocumentsContract.buildDocumentUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree),
        )
    }

    /** Archivos (no carpetas) de la carpeta: pares (identificador, nombre). */
    private fun listFiles(folder: String): List<Pair<String, String>> {
        val tree = tree(folder)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree),
        )
        val out = ArrayList<Pair<String, String>>()
        try {
            resolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null, null, null,
            )?.use { c ->
                while (c.moveToNext()) {
                    if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) continue
                    out.add(c.getString(0) to c.getString(1))
                }
            } ?: throw Fail("no_access", "No se puede leer la carpeta")
        } catch (e: Fail) {
            throw e
        } catch (e: SecurityException) {
            throw Fail("no_access", "Sin permiso para la carpeta")
        } catch (e: Exception) {
            throw Fail("no_access", "La carpeta ya no está disponible")
        }
        return out
    }

    private fun documentUri(folder: String, name: String): Uri {
        val id = listFiles(folder).firstOrNull { it.second == name }?.first
            ?: throw Fail("not_found", "No existe el archivo")
        return DocumentsContract.buildDocumentUriUsingTree(tree(folder), id)
    }

    private fun isAccessible(folder: String): Boolean {
        val tree = tree(folder)
        val granted = resolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission && it.isWritePermission
        }
        if (!granted) return false
        return try {
            listFiles(folder)
            true
        } catch (e: Fail) {
            false
        }
    }

    /**
     * Escribe con nombre temporal y renombra al terminar, así una copia a
     * medias nunca tiene el nombre de una copia.
     */
    private fun writeFile(folder: String, name: String, data: ByteArray) {
        val existing = listFiles(folder)
        if (existing.any { it.second == name }) {
            throw Fail("exists", "Ya existe un archivo con ese nombre")
        }
        val tmpName = "$name.tmp"
        existing.filter { it.second == tmpName }.forEach {
            DocumentsContract.deleteDocument(
                resolver,
                DocumentsContract.buildDocumentUriUsingTree(tree(folder), it.first),
            )
        }
        val tmp = try {
            DocumentsContract.createDocument(
                resolver, parentUri(folder), "application/octet-stream", tmpName,
            )
        } catch (e: Exception) {
            null
        } ?: throw Fail("no_access", "No se pudo crear el archivo en la carpeta")
        try {
            val fd = resolver.openFileDescriptor(tmp, "w")
                ?: throw Fail("io", "No se pudo abrir el archivo para escribir")
            fd.use {
                FileOutputStream(it.fileDescriptor).use { out ->
                    out.write(data)
                    out.flush()
                    out.fd.sync()
                }
            }
            DocumentsContract.renameDocument(resolver, tmp, name)
                ?: throw Fail("io", "No se pudo poner el nombre definitivo")
        } catch (e: Exception) {
            try {
                DocumentsContract.deleteDocument(resolver, tmp)
            } catch (_: Exception) {
            }
            throw if (e is Fail) e else Fail("io", "No se pudo escribir el archivo")
        }
    }

    private fun readFile(folder: String, name: String): ByteArray {
        val uri = documentUri(folder, name)
        try {
            return resolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw Fail("io", "No se pudo abrir el archivo")
        } catch (e: Fail) {
            throw e
        } catch (e: Exception) {
            throw Fail("io", "No se pudo leer el archivo")
        }
    }

    private fun deleteFile(folder: String, name: String) {
        val uri = documentUri(folder, name)
        val ok = try {
            DocumentsContract.deleteDocument(resolver, uri)
        } catch (e: Exception) {
            false
        }
        if (!ok) throw Fail("io", "No se pudo borrar el archivo")
    }

    // ---- Compartir --------------------------------------------------------

    private fun shareFile(name: String, mime: String, data: ByteArray) {
        val dir = File(activity.cacheDir, "export").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val file = File(dir, File(name).name)
        file.writeBytes(data)
        val uri = FileProvider.getUriForFile(
            activity, "${activity.packageName}.fileprovider", file,
        )
        val send = Intent(Intent.ACTION_SEND)
            .setType(mime)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(Intent.createChooser(send, null))
    }

    // ---- Utilidades -------------------------------------------------------

    private fun arg(call: MethodCall, key: String): String =
        call.argument<String>(key) ?: throw Fail("io", "Falta $key")

    private fun bytes(call: MethodCall): ByteArray =
        call.argument<ByteArray>("bytes") ?: throw Fail("io", "Faltan los datos")

    /** Hace el trabajo fuera del hilo principal y devuelve el resultado en él. */
    private fun background(
        result: MethodChannel.Result,
        onMain: Boolean = false,
        work: () -> Any?,
    ) {
        val run = Runnable {
            val outcome = try {
                Result.success(work())
            } catch (e: Fail) {
                Result.failure(e)
            } catch (e: SecurityException) {
                Result.failure(Fail("no_access", "Sin permiso"))
            } catch (e: Exception) {
                Result.failure(Fail("io", "Fallo de entrada/salida"))
            }
            main.post {
                outcome.fold(
                    { result.success(it) },
                    {
                        val f = it as Fail
                        result.error(f.code, f.message, null)
                    },
                )
            }
        }
        if (onMain) main.post(run) else io.execute(run)
    }

    private companion object {
        const val CHANNEL = "es.horasyvacaciones/storage"
        const val REQ_FOLDER = 4101
        const val REQ_FILE = 4102
    }
}
