package com.mindberzerk.g_family;

import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.ContentObserver;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Reads G VPN's status provider and starts its control activity.
 *
 * Every failure becomes a state ("notInstalled", "unavailable") rather than
 * an exception: the calling app always has something honest to show.
 *
 * Status reads run on a background thread. Querying G VPN's provider is a
 * cross-process call, and when G VPN is not running the system has to start
 * its process before the query returns. Done on the main thread that stalled
 * the host app's startup and Play reported it as an input-dispatch ANR in
 * {@code readStatus}. Results are always delivered back on the main thread.
 */
public final class GFamilyPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private static final String GVPN = "com.mindberzerk.gvpn";
    private static final Uri STATUS = Uri.parse("content://com.mindberzerk.gvpn.family/status");
    private static final String CONTROL_ACTIVITY = "com.mindberzerk.gvpn.GvpnControlActivity";

    private Context context;
    private MethodChannel calls;
    private EventChannel changes;
    private ContentObserver observer;
    private EventChannel.EventSink sink;
    private ExecutorService io;
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        io = Executors.newSingleThreadExecutor(r -> new Thread(r, "g_family-io"));
        calls = new MethodChannel(binding.getBinaryMessenger(), "com.mindberzerk.g_family");
        calls.setMethodCallHandler(this);
        changes = new EventChannel(binding.getBinaryMessenger(), "com.mindberzerk.g_family/changes");
        changes.setStreamHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        onCancel(null);
        calls.setMethodCallHandler(null);
        changes.setStreamHandler(null);
        io.shutdownNow();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "status":
                io.execute(() -> {
                    Map<String, Object> status = readStatus();
                    main.post(() -> result.success(status));
                });
                break;
            case "control":
                result.success(control(new Intent((String) call.arguments)));
                break;
            case "pause":
                Object minutes = call.arguments;
                result.success(control(new Intent("com.mindberzerk.gvpn.action.PAUSE")
                        .putExtra("minutes", minutes instanceof Integer ? (Integer) minutes : 15)));
                break;
            case "open":
                open((String) call.arguments);
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private Map<String, Object> readStatus() {
        Map<String, Object> out = new HashMap<>();
        if (!installed()) {
            out.put("state", "notInstalled");
            return out;
        }
        try (Cursor c = context.getContentResolver().query(STATUS, null, null, null, null)) {
            if (c == null || !c.moveToFirst()) {
                out.put("state", "unavailable");
                return out;
            }
            out.put("state", c.getString(c.getColumnIndexOrThrow("state")));
            out.put("label", c.getString(c.getColumnIndexOrThrow("label")));
            out.put("pausedUntil", c.getLong(c.getColumnIndexOrThrow("paused_until")));
        } catch (SecurityException | IllegalArgumentException e) {
            // Permission not granted to this app: see GVpnState.unavailable.
            out.put("state", "unavailable");
        }
        return out;
    }

    /** False when G VPN refused or is missing; the caller then opens it. */
    private boolean control(Intent intent) {
        if (!installed()) return false;
        intent.setClassName(GVPN, CONTROL_ACTIVITY).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(intent);
            return true;
        } catch (SecurityException | ActivityNotFoundException e) {
            open("g_family");
            return false;
        }
    }

    private void open(String referrer) {
        Intent launch = context.getPackageManager().getLaunchIntentForPackage(GVPN);
        if (launch == null) {
            launch = new Intent(Intent.ACTION_VIEW, Uri.parse(
                    "https://play.google.com/store/apps/details?id=" + GVPN
                            + "&referrer=utm_source%3D" + Uri.encode(referrer)));
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(launch);
        } catch (ActivityNotFoundException ignored) {
            // No Play Store and no browser: nothing more to try.
        }
    }

    private boolean installed() {
        try {
            context.getPackageManager().getPackageInfo(GVPN, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    // ── changes ──────────────────────────────────────────────────────────

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        sink = events;
        emitStatus(events);
        ContentResolver resolver = context.getContentResolver();
        observer = new ContentObserver(main) {
            @Override
            public void onChange(boolean selfChange) {
                emitStatus(events);
            }
        };
        try {
            resolver.registerContentObserver(STATUS, false, observer);
        } catch (SecurityException e) {
            observer = null;
        }
    }

    /**
     * Reads off the main thread and emits on it, but only while {@code events} is
     * still the live sink ({@code sink}): a read that finishes after a cancel or a re-listen
     * must not write into a stream nobody is listening to.
     */
    private void emitStatus(EventChannel.EventSink events) {
        if (io.isShutdown()) return;
        io.execute(() -> {
            Map<String, Object> status = readStatus();
            main.post(() -> {
                if (sink == events) events.success(status);
            });
        });
    }

    @Override
    public void onCancel(Object arguments) {
        sink = null;
        if (observer != null) {
            context.getContentResolver().unregisterContentObserver(observer);
            observer = null;
        }
    }
}
