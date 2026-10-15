// Local review packaging only; never linked into the ordinary application.
// This macOS sandbox API is deprecated. Fail closed if it stops working.
#include <CoreFoundation/CoreFoundation.h>
#include <sandbox.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include "ReviewProfile.h"

void sgf_install_offline_guard(void) {
    static int installed = 0;
    if (installed) return;
    CFStringRef identifier = CFBundleGetIdentifier(CFBundleGetMainBundle());
    if (!identifier || !CFEqual(identifier, CFSTR("com.davemarvit.SGFPlayerClean.offline-review"))) {
        fprintf(stderr, "Offline review refused to start: incorrect application identity.\n");
        exit(78);
    }
    char *error = NULL;
    if (sandbox_init(review_profile, 0, &error) != 0) {
        fprintf(stderr, "Offline review refused to start: network isolation failed: %s\n", error ? error : "unknown error");
        sandbox_free_error(error);
        exit(78);
    }
    installed = 1;
    fprintf(stderr, "Offline review: network block installed; separate application identity verified.\n");

    // Probe only loopback, never OGS or another external host. Used by the packaging check.
    if (getenv("SGF_REVIEW_CHECK")) {
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address = {0};
        address.sin_family = AF_INET;
        address.sin_port = htons(9);
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        int result = fd < 0 ? -1 : connect(fd, (struct sockaddr *)&address, sizeof(address));
        int blocked = result == -1 && (errno == EPERM || errno == EACCES);
        if (fd >= 0) close(fd);
        fprintf(stderr, "Offline review loopback probe: %s\n", blocked ? "BLOCKED" : "FAILED");
        exit(blocked ? 0 : 1);
    }
}
