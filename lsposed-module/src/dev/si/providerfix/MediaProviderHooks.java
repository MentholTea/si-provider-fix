package dev.si.providerfix;

import android.content.ContentValues;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;

import java.lang.reflect.Method;
import java.util.Arrays;

import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;

/**
 * MediaProvider-side half of the fix.
 *
 * Storage Isolation redirects an app by bind-mounting the export target over the export source
 * inside that app's own mount namespace. Writes that go through MediaStore never touch the app
 * namespace: MediaProvider resolves the relative_path in its own (unshifted) namespace, so the
 * file lands in the original folder. This hook applies the same export rule to the row that
 * MediaProvider is about to write, keyed by Binder.getCallingUid().
 */
public final class MediaProviderHooks {

    private static final String MEDIA_PROVIDER_CLASS = "com.android.providers.media.MediaProvider";
    private static final String COLUMN_RELATIVE_PATH = "relative_path";
    private static final String COLUMN_DATA = "_data";

    private MediaProviderHooks() {
    }

    public static void install(ClassLoader classLoader) {
        Class<?> mediaProvider;
        try {
            mediaProvider = Class.forName(MEDIA_PROVIDER_CLASS, false, classLoader);
        } catch (Throwable t) {
            Logx.w("MediaProvider class unavailable", t);
            Markers.write(MainHook.PKG_MEDIA_PROVIDER, "MediaProvider class missing " + t);
            return;
        }

        int hooked = 0;
        hooked += hook(mediaProvider, "insert", new Class[]{Uri.class, ContentValues.class}) ? 1 : 0;
        hooked += hook(mediaProvider, "insert",
                new Class[]{Uri.class, ContentValues.class, Bundle.class}) ? 1 : 0;
        hooked += hook(mediaProvider, "bulkInsert",
                new Class[]{Uri.class, ContentValues[].class}) ? 1 : 0;
        hooked += hook(mediaProvider, "update",
                new Class[]{Uri.class, ContentValues.class, String.class, String[].class}) ? 1 : 0;
        hooked += hook(mediaProvider, "update",
                new Class[]{Uri.class, ContentValues.class, Bundle.class}) ? 1 : 0;

        Markers.write(MainHook.PKG_MEDIA_PROVIDER, "MediaProvider hooks installed=" + hooked);
        Logx.i("MediaProvider hooks installed: " + hooked);
    }

    private static boolean hook(Class<?> clazz, String name, Class<?>[] parameterTypes) {
        try {
            Method method = clazz.getDeclaredMethod(name, parameterTypes);
            method.setAccessible(true);
            XposedBridge.hookMethod(method, new XC_MethodHook() {
                @Override
                protected void beforeHookedMethod(MethodHookParam param) {
                    try {
                        patchArgs(param.args);
                    } catch (Throwable t) {
                        Logx.w("patch failed", t);
                    }
                }
            });
            Logx.i("hooked " + name + Arrays.toString(parameterTypes));
            return true;
        } catch (Throwable t) {
            Logx.w("hook " + name + Arrays.toString(parameterTypes) + " failed", t);
            Markers.write(MainHook.PKG_MEDIA_PROVIDER,
                    "hook " + name + Arrays.toString(parameterTypes) + " failed " + t);
            return false;
        }
    }

    private static void patchArgs(Object[] args) {
        if (args == null) {
            return;
        }
        int uid = Binder.getCallingUid();
        if (uid <= 0) {
            return;
        }
        for (Object arg : args) {
            if (arg instanceof ContentValues) {
                patchValues((ContentValues) arg, uid);
            } else if (arg instanceof ContentValues[]) {
                for (ContentValues values : (ContentValues[]) arg) {
                    patchValues(values, uid);
                }
            }
        }
    }

    private static void patchValues(ContentValues values, int uid) {
        if (values == null) {
            return;
        }
        if (!values.containsKey(COLUMN_RELATIVE_PATH) && !values.containsKey(COLUMN_DATA)) {
            return;
        }
        String[] packages = UidUtil.packagesForUid(uid);
        if (packages.length == 0) {
            return;
        }
        String relativePath = values.getAsString(COLUMN_RELATIVE_PATH);
        String dataPath = values.getAsString(COLUMN_DATA);
        Markers.write(MainHook.PKG_MEDIA_PROVIDER, "write uid=" + uid
                + " pkgs=" + Arrays.toString(packages)
                + " rel=" + relativePath + " data=" + dataPath
                + " rules=" + RuleStore.ruleCount());
        for (String pkg : packages) {
            if (relativePath != null) {
                String mapped = RuleStore.mapRelativePath(pkg, relativePath);
                if (mapped != null) {
                    String applied = mapped.endsWith("/") ? mapped : mapped + "/";
                    values.put(COLUMN_RELATIVE_PATH, applied);
                    Markers.write(MainHook.PKG_MEDIA_PROVIDER, "redirect-rel uid=" + uid
                            + " pkg=" + pkg + " " + relativePath + " -> " + applied);
                    Logx.i("redirect relative_path uid=" + uid + " pkg=" + pkg
                            + " [" + relativePath + "] -> [" + applied + "]");
                    return;
                }
            }
            if (dataPath != null) {
                String mapped = RuleStore.mapAbsolutePath(pkg, dataPath);
                if (mapped != null) {
                    values.put(COLUMN_DATA, mapped);
                    Markers.write(MainHook.PKG_MEDIA_PROVIDER, "redirect-data uid=" + uid
                            + " pkg=" + pkg + " " + dataPath + " -> " + mapped);
                    Logx.i("redirect _data uid=" + uid + " pkg=" + pkg
                            + " [" + dataPath + "] -> [" + mapped + "]");
                    return;
                }
            }
        }
    }
}
