package dev.si.providerfix;

import java.io.File;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;

/**
 * Loads the native half of the MiShare guard.
 *
 * <p>MediaProvider creates {@code /storage/emulated/0/MiShare} through a native
 * {@code mkdirat(..., 0775)} issued from a FUSE worker thread. Every Java entry point has been
 * hooked and none of them sees the call, so the interception has to happen in libc. The native
 * library patches {@code mkdirat} in place and answers the matching path with success without
 * touching the filesystem.
 *
 * <p>LSPosed hands the module a class loader whose native search path points *inside* the APK
 * ({@code base.apk!/lib/arm64-v8a}), which {@code System.loadLibrary} cannot use. The library is
 * therefore located from the module APK path and loaded by absolute path; the APK path is derived
 * from the loader object itself (field first, string form as fallback).
 *
 * <p>Failure here is not fatal: the class only records the reason in the marker file and leaves
 * the process untouched.
 */
final class NativeHook {

    private static final String LIB_NAME = "libmishareguard.so";

    private static volatile boolean loaded;
    private static volatile boolean installed;

    private NativeHook() {
    }

    private static native int install();

    static synchronized void installIfPossible() {
        if (installed) {
            return;
        }
        if (!loaded) {
            String reason = load();
            if (reason != null) {
                Markers.write(MainHook.PKG_MEDIA_PROVIDER, "libmishareguard load failed " + reason);
                Logx.w("libmishareguard load failed: " + reason, null);
                return;
            }
            loaded = true;
        }
        try {
            int result = install();
            installed = result == 1;
            Markers.write(MainHook.PKG_MEDIA_PROVIDER, "mishare-native install=" + result);
            Logx.i("mishare-native install=" + result);
        } catch (Throwable t) {
            Markers.write(MainHook.PKG_MEDIA_PROVIDER, "mishare-native install failed " + t);
            Logx.w("mishare-native install failed", t);
        }
    }

    /** Returns null on success, otherwise the last failure reason. */
    private static String load() {
        try {
            System.loadLibrary("mishareguard");
            return null;
        } catch (Throwable ignored) {
            // fall through to the absolute-path strategy
        }
        String last = "no candidate";
        StringBuilder tried = new StringBuilder();
        for (String candidate : candidates()) {
            if (candidate == null) {
                continue;
            }
            tried.append(candidate).append(' ');
            try {
                if (new File(candidate).isFile()) {
                    System.load(candidate);
                    return null;
                }
            } catch (Throwable t) {
                last = t.toString();
            }
        }
        return last + " tried=[" + tried.toString().trim() + "]";
    }

    private static String[] candidates() {
        String abi = android.os.Process.is64Bit() ? "arm64" : "arm";
        List<String> out = new ArrayList<>();

        // 1) reflective: LspModuleClassLoader -> DexPathList.nativeLibraryDirectories
        try {
            ClassLoader cl = NativeHook.class.getClassLoader();
            Object pathList = readField(cl, "pathList");
            if (pathList == null) {
                pathList = readField(cl, "p1");
            }
            Object dirs = readField(pathList, "nativeLibraryDirectories");
            if (dirs instanceof Object[]) {
                for (Object dir : (Object[]) dirs) {
                    String path = String.valueOf(dir);
                    int bang = path.indexOf("!/");
                    if (bang > 0) {
                        out.add(apkToLib(path.substring(0, bang), abi));
                    }
                }
            }
        } catch (Throwable ignored) {
            // best effort only
        }

        // 2) textual: LspModuleClassLoader[module=/data/app/.../base.apk, ...]
        try {
            String desc = NativeHook.class.getClassLoader().toString();
            int start = desc.indexOf("module=");
            if (start >= 0) {
                int end = desc.indexOf(',', start);
                String apk = desc.substring(start + "module=".length(),
                        end > 0 ? end : desc.length());
                out.add(apkToLib(apk, abi));
            }
        } catch (Throwable ignored) {
            // best effort only
        }

        // 3) system paths, populated by a Magisk overlay if one is installed
        out.add("/system/lib64/" + LIB_NAME);
        out.add("/system_ext/lib64/" + LIB_NAME);
        return out.toArray(new String[0]);
    }

    private static String apkToLib(String apk, String abi) {
        if (apk == null) {
            return null;
        }
        int slash = apk.lastIndexOf('/');
        if (slash <= 0) {
            return null;
        }
        return apk.substring(0, slash) + "/lib/" + abi + "/" + LIB_NAME;
    }

    private static Object readField(Object target, String name) {
        if (target == null) {
            return null;
        }
        Class<?> type = target.getClass();
        while (type != null) {
            try {
                Field field = type.getDeclaredField(name);
                field.setAccessible(true);
                return field.get(target);
            } catch (NoSuchFieldException e) {
                type = type.getSuperclass();
            } catch (Throwable t) {
                return null;
            }
        }
        return null;
    }
}