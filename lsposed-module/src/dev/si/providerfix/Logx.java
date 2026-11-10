package dev.si.providerfix;

import android.util.Log;

public final class Logx {

    public static final String TAG = "SiProviderFix";

    private Logx() {
    }

    public static void i(String message) {
        Log.i(TAG, message);
    }

    public static void w(String message, Throwable throwable) {
        if (throwable == null) {
            Log.w(TAG, message);
        } else {
            Log.w(TAG, message, throwable);
        }
    }
}
