package dev.si.providerfix;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.Charset;

/**
 * Writes plain marker files so that module injection can be verified without logcat
 * (logcat is unusable on Android 17 / HyperOS here).
 *
 * The credential-encrypted data dir does not exist before first unlock, so the device-encrypted
 * dir is written first and the CE dir is used as a secondary sink.
 */
final class Markers {

    private static final String FILE_NAME = "si-provider-fix.marker";

    private Markers() {
    }

    static void write(String packageName, String message) {
        if (packageName == null) {
            return;
        }
        StringBuilder sinks = new StringBuilder();
        sinks.append("/data/user_de/0/").append(packageName);
        sinks.append('\n').append("/data/user/0/").append(packageName);
        for (String dir : sinks.toString().split("\n")) {
            appendTo(dir, packageName, message);
        }
    }

    private static void appendTo(String dataDir, String packageName, String message) {
        try {
            File dir = new File(dataDir, "files");
            if (!dir.isDirectory() && !dir.mkdirs()) {
                return;
            }
            File file = new File(dir, FILE_NAME);
            String line = System.currentTimeMillis()
                    + " uid=" + android.os.Process.myUid()
                    + " pid=" + android.os.Process.myPid()
                    + " pkg=" + packageName
                    + " " + message + "\n";
            FileOutputStream out = new FileOutputStream(file, true);
            try {
                out.write(line.getBytes(Charset.forName("UTF-8")));
                out.flush();
            } finally {
                out.close();
            }
            // keep the probe readable for the analyst shell account
            file.setReadable(true, false);
        } catch (Throwable ignored) {
            // injection probing must never break the host process
        }
    }
}
