package dev.si.providerfix;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Rule source for the MediaProvider side.
 *
 * MediaProvider is not in the KernelSU allow list, so it cannot run su itself. Rules are instead
 * pushed into a file it can read by two independent producers:
 *
 * 1. the root daemon installed by this module (survives, does not depend on any app process);
 * 2. the Storage Isolation manager hook (immediate push when the user edits a rule).
 *
 * Every write is served with a short TTL, effectively "read at write time".
 */
public final class RuleStore {

    /**
     * The only readable sink. /data/media is NOT readable by MediaProvider (verified: the
     * emulated volume entry is owned by media_rw), so it must never be consulted - a stale copy
     * there would shadow the good one.
     */
    public static final String RULES_PATH_DE =
            "/data/user_de/0/com.android.providers.media.module/files/si_provider_rules.json";

    /** Re-stat the file this often at most; cheap because the content is unchanged usually. */
    private static final long TTL_NANOS = java.util.concurrent.TimeUnit.SECONDS.toNanos(2L);

    public static final class Rule {
        public final String pkg;
        public final String source;
        public final String target;

        Rule(String pkg, String source, String target) {
            this.pkg = pkg;
            this.source = source;
            this.target = target;
        }
    }

    private static final Object LOCK = new Object();
    private static Map<String, List<Rule>> sByPackage = Collections.emptyMap();
    private static long sExpiresAtNanos = 0L;
    private static long sLoadedStamp = -1L;
    private static String sLastStatus = "not-loaded";

    private RuleStore() {
    }

    public static int ruleCount() {
        return snapshot().size();
    }

    public static String lastStatus() {
        return sLastStatus;
    }

    /**
     * Maps a MediaStore relative_path (e.g. "DCIM/HeyBox/shot.jpg") to the configured target.
     */
    public static String mapRelativePath(String pkg, String relativePath) {
        if (pkg == null || relativePath == null) {
            return null;
        }
        List<Rule> rules = snapshot().get(pkg);
        if (rules == null) {
            return null;
        }
        String normalized = stripLeadingSlashes(relativePath);
        for (Rule rule : rules) {
            if (rule.source.isEmpty()) {
                continue;
            }
            if (!normalized.equals(rule.source) && !normalized.startsWith(rule.source + "/")) {
                continue;
            }
            String rest = normalized.substring(rule.source.length());
            while (rest.startsWith("/")) {
                rest = rest.substring(1);
            }
            return rest.isEmpty() ? rule.target : rule.target + "/" + rest;
        }
        return null;
    }

    /**
     * Maps an absolute _data path under the emulated volume to the configured target.
     */
    public static String mapAbsolutePath(String pkg, String absolutePath) {
        if (pkg == null || absolutePath == null) {
            return null;
        }
        int marker = absolutePath.indexOf("/storage/emulated/");
        if (marker < 0) {
            return null;
        }
        int relativeStart = absolutePath.indexOf('/', marker + "/storage/emulated/".length());
        if (relativeStart < 0 || relativeStart + 1 >= absolutePath.length()) {
            return null;
        }
        String relative = absolutePath.substring(relativeStart + 1);
        String mapped = mapRelativePath(pkg, relative);
        if (mapped == null) {
            return null;
        }
        return absolutePath.substring(0, relativeStart + 1) + mapped;
    }

    private static Map<String, List<Rule>> snapshot() {
        synchronized (LOCK) {
            if (System.nanoTime() < sExpiresAtNanos) {
                return sByPackage;
            }
            Map<String, List<Rule>> parsed = Collections.emptyMap();
            String status;
            try {
                String raw = readNewest();
                long stamp = sLoadedStamp;
                parsed = parse(raw);
                status = "ok rules=" + countOf(parsed) + " stamp=" + stamp;
                sExpiresAtNanos = System.nanoTime() + TTL_NANOS;
            } catch (Throwable t) {
                status = "fail " + t;
                sExpiresAtNanos = System.nanoTime() + TTL_NANOS;
            }
            sByPackage = parsed;
            if (!status.equals(sLastStatus)) {
                sLastStatus = status;
                Markers.write(MainHook.PKG_MEDIA_PROVIDER, "rules " + status);
            }
            return sByPackage;
        }
    }

    private static int countOf(Map<String, List<Rule>> map) {
        int total = 0;
        for (List<Rule> list : map.values()) {
            total += list.size();
        }
        return total;
    }

    /**
     * Reads the snapshot. Only one sink is consulted: /data/media is not readable by
     * MediaProvider, and mixing sources let a stale copy shadow a fresh one.
     */
    private static String readNewest() {
        File file = new File(RULES_PATH_DE);
        if (!file.isFile() || !file.canRead()) {
            throw new IllegalStateException("rules file not readable");
        }
        String raw = readFile(RULES_PATH_DE);
        if (raw == null || raw.isEmpty()) {
            throw new IllegalStateException("rules file empty");
        }
        sLoadedStamp = file.lastModified();
        return raw;
    }

    private static Map<String, List<Rule>> parse(String raw) throws Exception {
        if (raw == null || raw.isEmpty()) {
            throw new IllegalStateException("empty rules");
        }
        JSONObject root = new JSONObject(raw);
        JSONArray rules = root.optJSONArray("rules");
        if (rules == null) {
            return Collections.emptyMap();
        }
        Map<String, List<Rule>> parsed = new HashMap<>();
        for (int i = 0; i < rules.length(); i++) {
            JSONObject item = rules.optJSONObject(i);
            if (item == null) {
                continue;
            }
            String pkg = item.optString("pkg", "").trim();
            String source = normalizeRelative(item.optString("source", ""));
            String target = normalizeRelative(item.optString("target", ""));
            if (pkg.isEmpty() || source.isEmpty() || target.isEmpty()) {
                continue;
            }
            List<Rule> list = parsed.get(pkg);
            if (list == null) {
                list = new ArrayList<>();
                parsed.put(pkg, list);
            }
            list.add(new Rule(pkg, source, target));
        }
        return parsed;
    }

    private static String readFile(String path) {
        InputStream in = null;
        try {
            in = new FileInputStream(path);
            ByteArrayOutputStream out = new ByteArrayOutputStream(4096);
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) > 0) {
                out.write(buffer, 0, read);
            }
            return out.toString("UTF-8");
        } catch (Throwable t) {
            return null;
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    static String normalizeRelative(String value) {
        if (value == null) {
            return "";
        }
        String normalized = value.trim();
        int emulated = normalized.indexOf("storage/emulated/");
        if (emulated >= 0) {
            int start = normalized.indexOf('/', emulated + "storage/emulated/".length());
            if (start >= 0) {
                normalized = normalized.substring(start + 1);
            }
        }
        normalized = stripLeadingSlashes(normalized);
        while (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return normalized;
    }

    private static String stripLeadingSlashes(String value) {
        String result = value;
        while (result.startsWith("/")) {
            result = result.substring(1);
        }
        return result;
    }
}
