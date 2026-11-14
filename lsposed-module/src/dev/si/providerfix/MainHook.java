package dev.si.providerfix;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.callbacks.XC_LoadPackage.LoadPackageParam;

public final class MainHook implements IXposedHookLoadPackage {

    static final String PKG_MEDIA_PROVIDER = "com.android.providers.media.module";
    static final String PKG_STORAGE_ISOLATION = "moe.shizuku.redirectstorage";

    @Override
    public void handleLoadPackage(LoadPackageParam lpparam) throws Throwable {
        // Probe first: this proves whether LSPosed delivered the load callback at all.
        try {
            String pkg = lpparam == null ? null : lpparam.packageName;
            String proc = lpparam == null ? null : lpparam.processName;
            Markers.write(pkg, "hook-enter pkg=" + pkg + " proc=" + proc);
        } catch (Throwable ignored) {
        }

        if (lpparam == null || lpparam.packageName == null) {
            return;
        }
        try {
            if (PKG_MEDIA_PROVIDER.equals(lpparam.packageName)) {
                Logx.i("loaded in MediaProvider process=" + lpparam.processName);
                Markers.write(lpparam.packageName, "media-provider-install");
                MediaProviderHooks.install(lpparam.classLoader);
                NativeHook.installIfPossible();
            } else if (PKG_STORAGE_ISOLATION.equals(lpparam.packageName)) {
                Logx.i("loaded in StorageIsolation process=" + lpparam.processName);
                Markers.write(lpparam.packageName, "storage-isolation-install");
                RulesExporter.install(lpparam.classLoader);
            }
        } catch (Throwable t) {
            XposedBridge.log(t);
            Logx.w("install failed for " + lpparam.packageName, t);
            Markers.write(lpparam.packageName, "install-failed " + t);
        }
    }
}
