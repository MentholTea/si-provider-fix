package dev.si.providerfix;

import android.content.Context;
import android.content.pm.PackageManager;

public final class UidUtil {

    private static volatile PackageManager sPackageManager;

    private UidUtil() {
    }

    public static String[] packagesForUid(int uid) {
        PackageManager pm = packageManager();
        if (pm == null) {
            return new String[0];
        }
        try {
            String[] packages = pm.getPackagesForUid(uid);
            return packages == null ? new String[0] : packages;
        } catch (Throwable t) {
            Logx.w("getPackagesForUid failed for " + uid, t);
            return new String[0];
        }
    }

    private static PackageManager packageManager() {
        PackageManager cached = sPackageManager;
        if (cached != null) {
            return cached;
        }
        try {
            Class<?> activityThread = Class.forName("android.app.ActivityThread");
            Object application = activityThread.getMethod("currentApplication").invoke(null);
            if (application instanceof Context) {
                cached = ((Context) application).getPackageManager();
                sPackageManager = cached;
            }
        } catch (Throwable t) {
            Logx.w("currentApplication unavailable", t);
        }
        return cached;
    }
}
