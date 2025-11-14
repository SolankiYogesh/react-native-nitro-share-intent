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
import androidx.core.net.toUri
import com.facebook.react.bridge.ActivityEventListener

@DoNotStrip
class NitroShareIntent : HybridNitroShareIntentSpec(), ActivityEventListener{

  private var intentListener: ((SharePayload) -> Unit)? = null
  private var pendingIntent: SharePayload? = null
  private var nextListenerId = 0.0

  companion object {
    val instance: NitroShareIntent by lazy { NitroShareIntent() }
  }

  fun handleIntent(intent: Intent?) {
    if (!isShareIntent(intent)) return
    val payload = processIntent(intent)
    if (payload != null) {
      intentListener?.invoke(payload)
      pendingIntent = payload
    }
  }

  init {
    NitroModules.applicationContext.let { ctx->
      ctx?.addActivityEventListener(this)
    }
  }


  override fun getInitialShare(): Promise<SharePayload?> {

    val intent = NitroModules.applicationContext?.currentActivity?.intent

    return if (intent != null && isShareIntent(intent)) {

      Promise.resolved(processIntent(intent))
    } else {
      Promise.resolved(SharePayload(ShareType.TEXT, null, null, null))
    }
  }

  override fun onIntentListener(listener: (SharePayload) -> Unit): Double {
    intentListener = listener
    nextListenerId++
    return nextListenerId
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
    val result = "com.android.externalstorage.documents" == uri.authority

    return result
  }

  private fun isDownloadsDocument(uri: Uri): Boolean {
    val result = "com.android.providers.downloads.documents" == uri.authority

    return result
  }

  private fun isMediaDocument(uri: Uri): Boolean {
    val result = "com.android.providers.media.documents" == uri.authority

    return result
  }

  private fun isShareIntent(intent: Intent?): Boolean {
    if (intent == null) {

      return false
    }
    val action = intent.action
    val result = action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE || action == Intent.ACTION_VIEW

    return result
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
  // TODO Auto-generated method stub
  }

  override fun onNewIntent(intent: Intent) {
handleIntent(intent)
  }


}
