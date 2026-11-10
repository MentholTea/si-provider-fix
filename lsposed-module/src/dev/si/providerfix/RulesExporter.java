package dev.si.providerfix;

import android.app.Application;
import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.reflect.Method;

import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;

/**
 * Storage Isolation side, immediate-push half.
 *
 * The authoritative producer is the root daemon installed by this module (see the magisk/
 * directory): it polls the configuration and survives independently of every app process.
 * This hook exists purely to remove the up-to-3-second latency after the user edits a rule,
 * by pushing a snapshot as soon as the Storage Isolation manager starts.
 *
 * If the manager never runs, the daemon already covers it.
 */
public final class RulesExporter {

    private static final String CONFIG_PATH = "/data/adb/storage-isolation/configuration.json";
    private static final String RULES_DE_DIR = "/data/user_de/0/com.android.providers.media.module/files";
    private static final String RULES_DE_PATH = RULES_DE_DIR + "/si_provider_rules.json";
    private static final String SU_BIN = "/system/bin/su";
    private static final String MEDIA_PROVIDER_UID = "10282";
    private static final String STAGING_PATH = "/data/local/tmp/si_provider_rules.json";

    private static volatile boolean sStarted;

    private RulesExporter() {
    }

    public static void install(ClassLoader classLoader) {
        hook(android.content.ContextWrapper.class, "attachBaseContext", new Class[]{Context.class});
        hook(Application.class, "onCreate", new Class[0]);
    }

    private static void hook(Class<?> clazz, String name, Class<?>[] parameterTypes) {
        try {
            Method method = clazz.getDeclaredMethod(name, parameterTypes);
            method.setAccessible(true);
            XposedBridge.hookMethod(method, new XC_MethodHook() {
                @Override
                protected void afterHookedMethod(MethodHookParam param) {
                    start();
                }
            });
            Markers.write("moe.shizuku.redirectstorage", name + " hooked on " + clazz.getName());
        } catch (Throwable t) {
            Markers.write("moe.shizuku.redirectstorage",
                    "hook " + name + " on " + clazz.getName() + " failed " + t);
        }
    }

    private static void start() {
        if (sStarted) {
            return;
        }
        sStarted = true;
        Thread thread = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    String result = pushOnce();
                    Markers.write("moe.shizuku.redirectstorage", "one-shot push " + result);
                } catch (Throwable t) {
                    Markers.write("moe.shizuku.redirectstorage", "one-shot push failed " + t);
                }
            }
        }, "si-provider-fix-push");
        thread.setDaemon(true);
        thread.start();
    }

    /**
     * One-shot push: the daemon handles everything else.
     */
    private static String pushOnce() throws Exception {
        String raw = suRead(CONFIG_PATH);
        if (raw == null || raw.isEmpty()) {
            return "empty-config";
        }
        JSONArray rules = new JSONArray();
        JSONArray observers = new JSONObject(raw).optJSONArray("observers");
        int count = 0;
        if (observers != null) {
            for (int i = 0; i < observers.length(); i++) {
                JSONObject observer = observers.optJSONObject(i);
                if (observer == null || !observer.optBoolean("enabled", true)) {
                    continue;
                }
                String pkg = observer.optString("package_name", "").trim();
                String source = RuleStore.normalizeRelative(observer.optString("source", ""));
                String target = RuleStore.normalizeRelative(observer.optString("target", ""));
                if (pkg.isEmpty() || source.isEmpty() || target.isEmpty()) {
                    continue;
                }
                JSONObject rule = new JSONObject();
                rule.put("pkg", pkg);
                rule.put("source", source);
                rule.put("target", target);
                rules.put(rule);
                count++;
            }
        }
        JSONObject snapshot = new JSONObject();
        snapshot.put("version", 1);
        snapshot.put("rules", rules);
        String write = suWrite(snapshot.toString());
        return write.length() == 0 ? "ok rules=" + count : "write-failed " + write;
    }

    private static String suRead(String remotePath) throws Exception {
        Process process = new ProcessBuilder(SU_BIN, "-c", "cat '" + remotePath + "'")
                .redirectErrorStream(true)
                .start();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        drainInto(process.getInputStream(), output);
        process.waitFor();
        String text = output.toString("UTF-8").trim();
        return text.isEmpty() ? null : text;
    }

    /**
     * The manager runs in Storage Isolation's own mount namespace where /data/user_de entries are
     * shadowed, so the final copy is executed by the init namespace (pid 1). The payload is
     * base64 inlined because KernelSU's su does not reliably forward stdin.
     */
    private static String suWrite(String content) throws Exception {
        String encoded = android.util.Base64.encodeToString(
                content.getBytes("UTF-8"), android.util.Base64.NO_WRAP);
        String inner = "mkdir -p " + RULES_DE_DIR
                + " && cp " + STAGING_PATH + " " + RULES_DE_PATH
                + " && chmod 644 " + RULES_DE_PATH
                + " && chown " + MEDIA_PROVIDER_UID + ":" + MEDIA_PROVIDER_UID + " " + RULES_DE_PATH;
        String command = "echo '" + encoded + "' | base64 -d > " + STAGING_PATH
                + " && nsenter -t 1 -m -- sh -c '" + inner + "'";
        Process process = new ProcessBuilder(SU_BIN, "-c", command)
                .redirectErrorStream(true)
                .start();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        drainInto(process.getInputStream(), output);
        int exit = process.waitFor();
        return exit == 0 ? "" : "exit=" + exit + " " + output.toString("UTF-8").trim();
    }

    private static void drainInto(InputStream input, ByteArrayOutputStream sink) throws Exception {
        byte[] buffer = new byte[4096];
        int read;
        while ((read = input.read(buffer)) > 0) {
            if (sink.size() < 256 * 1024) {
                sink.write(buffer, 0, read);
            }
        }
    }
}
