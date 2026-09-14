package com.aryansaproo.content_maker;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.FileProvider;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
  private static final String PICKER_CHANNEL = "content_maker/file_picker";
  private static final String SHARE_CHANNEL = "content_maker/share";
  private static final int PICK_DOCUMENT_REQUEST = 4107;

  @Nullable private MethodChannel.Result pendingResult;
  @Nullable private String pendingMethod;

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), PICKER_CHANNEL)
        .setMethodCallHandler(
            (call, result) -> {
              switch (call.method) {
                case "pickVideos":
                  openDocument("video/*", true, call.method, result);
                  break;
                case "pickVideo":
                  openDocument("video/*", false, call.method, result);
                  break;
                case "pickAudio":
                  openDocument("audio/*", false, call.method, result);
                  break;
                case "pickProject":
                  openDocument("application/octet-stream", false, call.method, result);
                  break;
                default:
                  result.notImplemented();
              }
            });
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SHARE_CHANNEL)
        .setMethodCallHandler(
            (call, result) -> {
              if (!"shareVideo".equals(call.method)) {
                result.notImplemented();
                return;
              }
              String path = call.argument("path");
              String caption = call.argument("caption");
              try {
                shareVideo(path, caption);
                result.success(true);
              } catch (IOException | IllegalArgumentException exception) {
                result.error("share_failed", "Content Maker could not share that video.", null);
              }
            });
  }

  private void shareVideo(@Nullable String path, @Nullable String caption) throws IOException {
    if (path == null || path.isEmpty()) {
      throw new IllegalArgumentException("A video path is required.");
    }
    File source = new File(path);
    if (!source.isFile()) {
      throw new IOException("The rendered video does not exist.");
    }

    File shareDirectory = new File(getCacheDir(), "shared_exports");
    if (!shareDirectory.exists() && !shareDirectory.mkdirs()) {
      throw new IOException("Could not create the share directory.");
    }
    File sharedVideo = new File(shareDirectory, source.getName());
    try (InputStream input = new java.io.FileInputStream(source);
        FileOutputStream output = new FileOutputStream(sharedVideo)) {
      copyStream(input, output);
    }

    Uri contentUri =
        FileProvider.getUriForFile(this, getPackageName() + ".files", sharedVideo);
    Intent shareIntent = new Intent(Intent.ACTION_SEND);
    shareIntent.setType("video/*");
    shareIntent.putExtra(Intent.EXTRA_STREAM, contentUri);
    shareIntent.setClipData(ClipData.newRawUri("Content Maker export", contentUri));
    shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    if (caption != null && !caption.trim().isEmpty()) {
      shareIntent.putExtra(Intent.EXTRA_TEXT, caption);
    }
    startActivity(Intent.createChooser(shareIntent, "Publish your video"));
  }

  private void openDocument(
      String mimeType,
      boolean allowMultiple,
      String method,
      MethodChannel.Result result) {
    if (pendingResult != null) {
      result.error("picker_busy", "A media picker is already open.", null);
      return;
    }

    pendingResult = result;
    pendingMethod = method;
    Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    intent.addCategory(Intent.CATEGORY_OPENABLE);
    intent.setType(mimeType);
    intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple);
    startActivityForResult(intent, PICK_DOCUMENT_REQUEST);
  }

  @Override
  protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
    super.onActivityResult(requestCode, resultCode, data);
    if (requestCode != PICK_DOCUMENT_REQUEST || pendingResult == null) {
      return;
    }

    MethodChannel.Result result = pendingResult;
    String method = pendingMethod;
    pendingResult = null;
    pendingMethod = null;

    if (resultCode != Activity.RESULT_OK || data == null) {
      result.success(null);
      return;
    }

    try {
      List<String> paths = copySelectionsToCache(data);
      if ("pickVideos".equals(method)) {
        result.success(paths);
      } else {
        result.success(paths.isEmpty() ? null : paths.get(0));
      }
    } catch (IOException exception) {
      result.error("picker_copy_failed", "Content Maker could not read that file.", null);
    }
  }

  private List<String> copySelectionsToCache(Intent data) throws IOException {
    ArrayList<String> paths = new ArrayList<>();
    ClipData clipData = data.getClipData();
    if (clipData != null) {
      for (int index = 0; index < clipData.getItemCount(); index++) {
        paths.add(copyToCache(clipData.getItemAt(index).getUri()));
      }
    } else if (data.getData() != null) {
      paths.add(copyToCache(data.getData()));
    }
    return paths;
  }

  private String copyToCache(Uri uri) throws IOException {
    File importsDirectory = new File(getFilesDir(), "imports");
    if (!importsDirectory.exists() && !importsDirectory.mkdirs()) {
      throw new IOException("Could not create the import directory.");
    }

    String displayName = queryDisplayName(uri);
    String safeName = displayName.replaceAll("[^A-Za-z0-9._-]", "_");
    if (safeName.isEmpty()) {
      safeName = "media";
    }
    File destination = new File(importsDirectory, System.nanoTime() + "_" + safeName);

    try (InputStream input = getContentResolver().openInputStream(uri);
        FileOutputStream output = new FileOutputStream(destination)) {
      if (input == null) {
        throw new IOException("The selected document could not be opened.");
      }
      copyStream(input, output);
    }
    return destination.getAbsolutePath();
  }

  private void copyStream(InputStream input, FileOutputStream output) throws IOException {
    byte[] buffer = new byte[64 * 1024];
    int bytesRead;
    while ((bytesRead = input.read(buffer)) != -1) {
      output.write(buffer, 0, bytesRead);
    }
  }

  private String queryDisplayName(Uri uri) {
    try (Cursor cursor =
        getContentResolver().query(uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
      if (cursor != null && cursor.moveToFirst()) {
        int nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
        if (nameColumn >= 0) {
          String name = cursor.getString(nameColumn);
          if (name != null && !name.isEmpty()) {
            return name;
          }
        }
      }
    }
    return "media";
  }
}
