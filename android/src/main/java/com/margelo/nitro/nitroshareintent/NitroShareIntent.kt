package com.margelo.nitro.nitroshareintent

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Intent
import android.database.Cursor
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Parcelable
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import java.io.File
import java.io.FileOutputStream
import java.util.Date
import java.util.concurrent.ConcurrentHashMap
import androidx.core.net.toUri
import com.facebook.react.bridge.ActivityEventListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@DoNotStrip
class NitroShareIntent : HybridNitroShareIntentSpec(), ActivityEventListener{

  // Keyed maps so multiple `useShareIntent()` hook instances (or any other
  // caller) can each register their own listener without stomping on one
  // another. `nextListenerId` is shared across both listener kinds so ids
  // stay unique and `removeListener` can safely look up either map.
  private val intentListeners = ConcurrentHashMap<Double, (SharePayload) -> Unit>()
  private val errorListeners = ConcurrentHashMap<Double, (String) -> Unit>()
  @Volatile
  private var pendingIntent: SharePayload? = null

  // Cache of the processed `getInitialShare()` result so repeated calls
  // don't re-read/re-copy `currentActivity.intent` (e.g. re-copying large
  // content:// files) from scratch every time.
  @Volatile
  private var hasCachedInitialShare = false
  @Volatile
  private var cachedInitialShare: SharePayload? = null

  private var nextListenerId = 0.0

  // Background scope used so large file copies never block the thread that
  // delivered the intent (e.g. the main/UI thread via `onNewIntent`).
  private val moduleScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

  companion object {
    private const val TAG = "NitroShareIntent"
    val instance: NitroShareIntent by lazy { NitroShareIntent() }
  }

  fun handleIntent(intent: Intent?) {
    if (!isShareIntent(intent)) return
    moduleScope.launch {
      try {
        val payload = processIntent(intent)
        if (payload != null) {
          pendingIntent = payload
          hasCachedInitialShare = true
          cachedInitialShare = payload
          notifyListeners(payload)
        }
      } catch (e: Exception) {
        Log.e(TAG, "Failed to process incoming share intent", e)
        notifyError("Failed to process incoming share intent: ${e.message}")
      }
    }
  }

  override fun getInitialShare(): Promise<SharePayload?> {
    if (hasCachedInitialShare) {
      return Promise.resolved(cachedInitialShare)
    }

    val activity = NitroModules.applicationContext?.currentActivity
    if (activity == null) {
      // The activity isn't attached to the React context yet (early startup,
      // or the process was restored in the background). Resolve as "nothing
      // shared" for this call, but *don't* cache it - the launch intent is
      // still sitting on the activity, and caching here would drop the share
      // permanently for the rest of the process' life.
      return Promise.resolved(null)
    }

    val intent = activity.intent

    if (intent == null || !isShareIntent(intent)) {
      hasCachedInitialShare = true
      cachedInitialShare = null
      return Promise.resolved(null)
    }

    return Promise.async {
      withContext(Dispatchers.IO) {
        try {
          val payload = processIntent(intent)
          hasCachedInitialShare = true
          cachedInitialShare = payload
          payload
        } catch (e: Exception) {
          Log.e(TAG, "Failed to read/parse the pending share intent", e)
          notifyError("Failed to read/parse the pending share intent: ${e.message}")
          throw e
        }
      }
    }
  }

  init {
    NitroModules.applicationContext.let { ctx->
      ctx?.addActivityEventListener(this)
    }
  }

  override fun onIntentListener(listener: (SharePayload) -> Unit): Double {
    nextListenerId++
    val id = nextListenerId
    intentListeners[id] = listener

    // Replay a pending intent to a newly attached listener, matching the
    // behavior already present on iOS, so shares that happened before the
    // JS listener attached aren't lost.
    pendingIntent?.let { pending ->
      listener(pending)
    }

    return id
  }

  override fun onErrorListener(listener: (String) -> Unit): Double {
    nextListenerId++
    val id = nextListenerId
    errorListeners[id] = listener
    return id
  }

  override fun removeListener(listenerId: Double) {
    intentListeners.remove(listenerId)
    errorListeners.remove(listenerId)
  }

  override fun clearShareIntent() {
    pendingIntent = null
    hasCachedInitialShare = false
    cachedInitialShare = null
  }

  private fun notifyListeners(payload: SharePayload) {
    intentListeners.values.forEach { it.invoke(payload) }
  }

  private fun notifyError(message: String) {
    errorListeners.values.forEach { it.invoke(message) }
  }

  private fun processIntent(intent: Intent?): SharePayload? {
    if (intent == null) return null

    val action = intent.action
    val type = intent.type

    val payload: SharePayload? = when (action) {
      Intent.ACTION_SEND -> {
        if (type != null) handleSingleShare(intent, type) else null
      }

      Intent.ACTION_SEND_MULTIPLE -> {
        if (type != null) handleMultipleShare(intent) else null
      }

      Intent.ACTION_VIEW -> {
        intent.dataString?.let { dataString ->
          val extras = mutableMapOf("url" to dataString)
          SharePayload(
            type = ShareType.TEXT,
            text = dataString,
            files = null,
            extras = extras
          )
        }
      }

      else -> {
        null
      }
    }

    return payload
  }

  private fun handleSingleShare(intent: Intent, type: String): SharePayload? {
    return when {
      type.startsWith("text/") -> {
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val title = intent.getCharSequenceExtra(Intent.EXTRA_TITLE)

        if (sharedText != null) {
          val extras = mutableMapOf<String, String>()
          subject?.let { extras["subject"] = it }
          title?.let { extras["title"] = it.toString() }

          SharePayload(ShareType.TEXT, sharedText, null, extras)
        } else null
      }

      else -> {
        val fileUri = intent.parcelable<Uri>(Intent.EXTRA_STREAM)
        if (fileUri != null) {
          val fileInfo = getFileInfo(fileUri)

          val extras = mutableMapOf<String, String>()
          fileInfo.forEach { (k, v) -> if (v != null) extras[k] = v }
          val filePath = fileInfo["filePath"] ?: fileUri.toString()

          SharePayload(ShareType.FILE, null, arrayOf(filePath), extras)
        } else null
      }
    }
  }

  private fun handleMultipleShare(intent: Intent): SharePayload? {
    val fileUris = intent.parcelableArrayList<Uri>(Intent.EXTRA_STREAM)

    if (fileUris.isNullOrEmpty()) return null

    val extras = mutableMapOf<String, String>()
    intent.getStringExtra(Intent.EXTRA_TEXT)?.let { extras["text"] = it }
    intent.getStringExtra(Intent.EXTRA_SUBJECT)?.let { extras["subject"] = it }
    extras["fileCount"] = fileUris.size.toString()

    val filePaths = fileUris.map { uri ->
      try {
        val fileInfo = getFileInfo(uri)
        fileInfo["filePath"] ?: uri.toString()
      } catch (_: Exception) {
        uri.toString()
      }
    }.toTypedArray()

    return SharePayload(ShareType.MULTIPLE, null, filePaths, extras)
  }

  @SuppressLint("Range")
  private fun getFileInfo(uri: Uri): Map<String, String?> {
    NitroModules.applicationContext.let { ctx ->
      val resolver: ContentResolver = ctx?.contentResolver ?: return mapOf(
        "contentUri" to uri.toString(),
        "filePath" to getAbsolutePath(uri),
      )
      val queryResult = resolver.query(uri, null, null, null, null)
      if (queryResult == null) {
        return mapOf("filePath" to getAbsolutePath(uri))
      }

      queryResult.moveToFirst()
      val fileName = queryResult.getString(queryResult.getColumnIndex(OpenableColumns.DISPLAY_NAME))
      val fileSize = queryResult.getString(queryResult.getColumnIndex(OpenableColumns.SIZE))
      queryResult.close()

      val mimeType = resolver.getType(uri) ?: "application/octet-stream"
      var mediaWidth: String? = null
      var mediaHeight: String? = null
      var mediaDuration: String? = null

      if (mimeType.startsWith("image/")) {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeStream(resolver.openInputStream(uri), null, options)
        mediaHeight = options.outHeight.toString()
        mediaWidth = options.outWidth.toString()
      }

      if (mimeType.startsWith("video/")) {
        try {
          val retriever = MediaMetadataRetriever()
          retriever.setDataSource(ctx, uri)
          mediaWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
          mediaHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
          val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
          if (rotation == 90 || rotation == 270) {
            val tmp = mediaWidth
            mediaWidth = mediaHeight
            mediaHeight = tmp
          }
          mediaDuration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
          retriever.release()
        } catch (e: Exception) {
          Log.e("NitroShareIntent", "Cannot retrieve video metadata for $uri", e)
        }
      }

      val info = mapOf(
        "contentUri" to uri.toString(),
        "filePath" to getAbsolutePath(uri),
        "fileName" to fileName,
        "fileSize" to fileSize,
        "mimeType" to mimeType,
        "width" to mediaWidth,
        "height" to mediaHeight,
        "duration" to mediaDuration
      )

      return info
    }
  }


  private fun getAbsolutePath(uri: Uri): String? {
    NitroModules.applicationContext.let { ctx ->
      try {
        if (DocumentsContract.isDocumentUri(ctx, uri)) {
          if (isExternalStorageDocument(uri)) {
            val docId = DocumentsContract.getDocumentId(uri)
            val split = docId.split(":".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
            val type = split[0]
            return if ("primary".equals(type, ignoreCase = true)) {
              Environment.getExternalStorageDirectory().toString() + "/" + split[1]
            } else getDataColumn(uri, null, null)
          } else if (isDownloadsDocument(uri)) {
            return try {
              val id = DocumentsContract.getDocumentId(uri)
              val contentUri = ContentUris.withAppendedId(
                "content://downloads/public_downloads".toUri(),
                java.lang.Long.valueOf(id)
              )
              getDataColumn(contentUri, null, null)
            } catch (_: Exception) {
              getDataColumn(uri, null, null)
            }
          } else if (isMediaDocument(uri)) {
            val docId = DocumentsContract.getDocumentId(uri)
            val split = docId.split(":".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
            val type = split[0]
            var contentUri: Uri? = null
            when (type) {
              "image" -> contentUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
              "video" -> contentUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
              "audio" -> contentUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }
            if (contentUri == null) return null
            val selection = "_id=?"
            val selectionArgs = arrayOf(split[1])
            return getDataColumn(contentUri, selection, selectionArgs)
          }
        } else if ("content".equals(uri.scheme, ignoreCase = true)) {
          return getDataColumn(uri, null, null)
        }

        return uri.path
      } catch (e: Exception) {
        Log.e("NitroShareIntent", "Cannot retrieve absolute file path for $uri", e)
        return null
      }
    }
  }

  private fun getDataColumn(uri: Uri, selection: String?, selectionArgs: Array<String>?): String? {
    NitroModules.applicationContext.let { ctx ->
      val resolver = ctx?.contentResolver
      if (uri.authority != null) {
        var cursor: Cursor? = null
        val column = "_display_name"
        val projection = arrayOf(column)
        var targetFile: File? = null

        try {
          cursor = resolver?.query(uri, projection, selection, selectionArgs, null)
          if (cursor != null && cursor.moveToFirst()) {
            val columnIndex = cursor.getColumnIndexOrThrow(column)
            val fileName = cursor.getString(columnIndex)

            targetFile = File(ctx?.cacheDir, fileName)
          }
        } finally {
          cursor?.close()
        }

        if (targetFile == null) {
          val mimeType = resolver?.getType(uri)
          val prefix = with(mimeType ?: "") {
            when {
              startsWith("image") -> "IMG"
              startsWith("video") -> "VID"
              else -> "FILE"
            }
          }
          val type = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
          targetFile = File(ctx?.cacheDir, "${prefix}_${Date().time}.$type")
        }

        resolver?.openInputStream(uri)?.use { input ->
          FileOutputStream(targetFile).use { fileOut ->
            input.copyTo(fileOut)
          }
        }

        return targetFile.path
      }

      var cursor: Cursor? = null
      val column = "_data"
      val projection = arrayOf(column)
      try {
        cursor = resolver?.query(uri, projection, selection, selectionArgs, null)
        if (cursor != null && cursor.moveToFirst()) {
          val columnIndex = cursor.getColumnIndexOrThrow(column)
          val result = cursor.getString(columnIndex)
          return result
        }
      } finally {
        cursor?.close()
      }

      return null
    }
  }

  private fun isExternalStorageDocument(uri: Uri): Boolean {
    return "com.android.externalstorage.documents" == uri.authority
  }

  private fun isDownloadsDocument(uri: Uri): Boolean {
    return "com.android.providers.downloads.documents" == uri.authority
  }

  private fun isMediaDocument(uri: Uri): Boolean {
    return "com.android.providers.media.documents" == uri.authority
  }

  private fun isShareIntent(intent: Intent?): Boolean {
    if (intent == null) {
      return false
    }
    val action = intent.action
    return action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE || action == Intent.ACTION_VIEW
  }

  inline fun <reified T : Parcelable> Intent.parcelable(key: String): T? {
    return if (Build.VERSION.SDK_INT >= 33) {
      getParcelableExtra(key, T::class.java)
    } else {
      @Suppress("DEPRECATION")
      getParcelableExtra(key) as? T
    }
  }

  inline fun <reified T : Parcelable> Intent.parcelableArrayList(key: String): ArrayList<T>? {
    return if (Build.VERSION.SDK_INT >= 33) {
      getParcelableArrayListExtra(key, T::class.java)
    } else {
      @Suppress("DEPRECATION")
      getParcelableArrayListExtra(key)
    }
  }

  override fun onActivityResult(
    activity: Activity,
    requestCode: Int,
    resultCode: Int,
    data: Intent?
  ) {
  }

  override fun onNewIntent(intent: Intent) {
    handleIntent(intent)
  }


}
