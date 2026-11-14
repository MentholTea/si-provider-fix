/*
 * Blocks MediaProvider (and other hooked processes) from creating stray directories in the
 * shared-storage root.
 *
 * strace on the MediaProvider process shows how MiShare appears:
 *
 *   9420 mkdirat(AT_FDCWD, "/storage/emulated/0/MiShare", 0775) = 0
 *
 * The call comes from a FUSE worker thread, i.e. below every Java entry point, so an Xposed hook
 * on File.mkdirs / File.mkdir / Os.mkdir / libcore.io.Linux.mkdir never sees it. This library
 * patches the libc entry points in place: a matching path is answered with success and nothing is
 * created, every other path goes to the original implementation.
 *
 * Both mkdirat and mkdir are covered. Current builds reach the directory through mkdirat, but
 * bionic's mkdir is a separate syscall wrapper and a ROM change could switch to it.
 *
 * Blocked list (directory names directly under a storage root):
 *   MiShare              re-created by MediaProvider on every process start
 *   com.miui.voiceassist  created by the voice assistant, empty audio/ shell
 *
 * Sub-paths and everything else (Download/MiShare included) are untouched: the match requires the
 * path to be exactly <root><name> or <root><name>/.
 */
#include <jni.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <dlfcn.h>
#include <android/log.h>

#define LOG_TAG "MiShareGuard"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

typedef int (*mkdirat_fn)(int, const char *, unsigned int);
typedef int (*mkdir_fn)(const char *, unsigned int);

static mkdirat_fn orig_mkdirat = NULL;
static mkdir_fn orig_mkdir = NULL;
static int installed = 0;

/* Directories that must never be created directly under a storage root. */
static const char *kBlockedDirs[] = {
        "MiShare",
        "com.miui.voiceassist",
};

/* Every prefix a directory-creating call may use for the same on-disk root. */
static const char *kRootPrefixes[] = {
        "/storage/emulated/0/",
        "/storage/self/primary/",
        "/data/media/0/",
        "/mnt/user/0/primary/",
        "/mnt/runtime/default/emulated/0/",
        "/mnt/runtime/read/emulated/0/",
        "/mnt/runtime/write/emulated/0/",
};

static int is_target_path(const char *path) {
    if (path == NULL) {
        return 0;
    }
    size_t plen = strlen(path);
    for (size_t r = 0; r < sizeof(kRootPrefixes) / sizeof(kRootPrefixes[0]); r++) {
        size_t rlen = strlen(kRootPrefixes[r]);
        if (plen <= rlen || strncmp(path, kRootPrefixes[r], rlen) != 0) {
            continue;
        }
        const char *rest = path + rlen;
        size_t restlen = plen - rlen;
        for (size_t b = 0; b < sizeof(kBlockedDirs) / sizeof(kBlockedDirs[0]); b++) {
            size_t blen = strlen(kBlockedDirs[b]);
            if (restlen == blen && strncmp(rest, kBlockedDirs[b], blen) == 0) {
                return 1;
            }
            if (restlen == blen + 1 && strncmp(rest, kBlockedDirs[b], blen) == 0
                    && rest[blen] == '/') {
                return 1;
            }
        }
    }
    return 0;
}

static int hook_mkdirat(int dirfd, const char *path, unsigned int mode) {
    if (is_target_path(path)) {
        LOGI("blocked mkdirat: %s", path);
        return 0;
    }
    return orig_mkdirat(dirfd, path, mode);
}

static int hook_mkdir(const char *path, unsigned int mode) {
    if (is_target_path(path)) {
        LOGI("blocked mkdir: %s", path);
        return 0;
    }
    return orig_mkdir(path, mode);
}

static void *page_start(void *p) {
    return (void *) ((uintptr_t) p & ~(uintptr_t) (getpagesize() - 1));
}

/*
 * Replaces the first 16 bytes of the resolved symbol with an absolute jump to `replacement`. The
 * displaced instructions are copied into a freshly mapped trampoline that jumps back to
 * `target + 16`, so the original implementation stays callable through `orig_out`.
 */
static int install_hook(const char *symbol, void *replacement, void **orig_out) {
    void *target = dlsym(RTLD_DEFAULT, symbol);
    if (target == NULL) {
        LOGI("%s not found", symbol);
        return 0;
    }

    uint32_t saved[4];
    memcpy(saved, target, sizeof(saved));
    for (int i = 0; i < 4; i++) {
        uint32_t op = saved[i] >> 26;
        if (op == 0x05 || op == 0x25) {
            LOGI("%s: refusing, prologue contains a direct branch", symbol);
            return 0;
        }
    }

    void *trampoline = mmap(NULL, 4096, PROT_READ | PROT_WRITE | PROT_EXEC,
                            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (trampoline == MAP_FAILED) {
        LOGI("%s: trampoline mmap failed", symbol);
        return 0;
    }
    uint32_t *tp = (uint32_t *) trampoline;
    memcpy(tp, saved, sizeof(saved));
    tp[4] = 0x58000050; /* ldr x16, #8 */
    tp[5] = 0xD61F0200; /* br  x16    */
    *(uint64_t *) (tp + 6) = (uint64_t) ((uintptr_t) target + 16);

    void *pg = page_start(target);
    if (mprotect(pg, getpagesize() * 2, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
        LOGI("%s: mprotect failed", symbol);
        munmap(trampoline, 4096);
        return 0;
    }
    uint32_t *t = (uint32_t *) target;
    t[0] = 0x58000050;
    t[1] = 0xD61F0200;
    *(uint64_t *) (t + 2) = (uint64_t) replacement;
    __builtin___clear_cache((char *) target, (char *) target + 16);

    *orig_out = trampoline;
    LOGI("%s hooked at %p, trampoline=%p", symbol, target, trampoline);
    return 1;
}

JNIEXPORT jint JNICALL
Java_dev_si_providerfix_NativeHook_install(JNIEnv *env, jclass clazz) {
    (void) env;
    (void) clazz;
    if (installed) {
        return 1;
    }
    int hooked = 0;
    hooked += install_hook("mkdirat", (void *) hook_mkdirat, (void **) &orig_mkdirat);
    hooked += install_hook("mkdir", (void *) hook_mkdir, (void **) &orig_mkdir);
    installed = hooked > 0;
    LOGI("hooks installed=%d", hooked);
    return installed;
}
