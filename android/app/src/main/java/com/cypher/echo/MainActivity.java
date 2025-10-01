package com.cypher.echo;

import android.content.Context;
import android.net.wifi.WifiManager;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "echo.lan/multicast";
    private WifiManager.MulticastLock multicastLock;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("acquire".equals(call.method)) {
                        try {
                            WifiManager wifi = (WifiManager) getApplicationContext()
                                    .getSystemService(Context.WIFI_SERVICE);

                            if (wifi == null) {
                                result.error("NO_WIFI", "WifiManager not available", null);
                                return;
                            }

                            if (multicastLock == null) {
                                multicastLock = wifi.createMulticastLock("echoLanLock");
                                multicastLock.setReferenceCounted(false);
                            }

                            if (!multicastLock.isHeld()) {
                                multicastLock.acquire();
                            }

                            result.success(true);
                        } catch (Exception e) {
                            result.error("ERR", e.toString(), null);
                        }
                        return;
                    }

                    if ("release".equals(call.method)) {
                        try {
                            if (multicastLock != null && multicastLock.isHeld()) {
                                multicastLock.release();
                            }
                            result.success(true);
                        } catch (Exception e) {
                            result.error("ERR", e.toString(), null);
                        }
                        return;
                    }

                    result.notImplemented();
                });
    }
}