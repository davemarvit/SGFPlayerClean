// OGS review only. Install before constructing any application model or client.
#include <CoreFoundation/CoreFoundation.h>
#include <sandbox.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>
#include "ReviewProfile.h"

void sgf_install_ogs_review_guard(void) {
    static int installed = 0;
    if (installed) return;
    CFStringRef identifier = CFBundleGetIdentifier(CFBundleGetMainBundle());
    if (!identifier || !CFEqual(identifier, CFSTR("com.davemarvit.SGFPlayerClean.ogs-review"))) {
        fprintf(stderr, "OGS review refused to start: incorrect application identity.\n");
        exit(78);
    }
    char *error = NULL;
    if (sandbox_init(review_profile, 0, &error) != 0) {
        fprintf(stderr, "OGS review refused to start: file protection failed: %s\n", error ? error : "unknown error");
        sandbox_free_error(error);
        exit(78);
    }
    installed = 1;
    fprintf(stderr, "OGS review: file protection installed; separate application identity verified.\n");

    if (getenv("SGF_REVIEW_CHECK")) {
        // A disposable sentinel uses the same deny rule as the protected originals.
        // Open without truncation and never write, even if protection is broken.
        int probe = open(review_write_probe, O_WRONLY);
        int ok = probe == -1 && (errno == EPERM || errno == EACCES);
        if (probe >= 0) close(probe);
        fprintf(stderr, "Protected-file write-open probe: %s\n", ok ? "BLOCKED" : "FAIL");
        // Verify networking is enabled against our own loopback listener, never OGS.
        int listener = socket(AF_INET, SOCK_STREAM, 0), client = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address = {0};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        socklen_t length = sizeof(address);
        int connected = listener >= 0 && client >= 0 &&
            bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0 &&
            getsockname(listener, (struct sockaddr *)&address, &length) == 0 &&
            listen(listener, 1) == 0 &&
            connect(client, (struct sockaddr *)&address, sizeof(address)) == 0;
        if (client >= 0) close(client);
        if (listener >= 0) close(listener);
        fprintf(stderr, "Loopback networking enabled: %s\n", connected ? "PASS" : "FAIL");
        exit(ok && connected ? 0 : 1);
    }
}
