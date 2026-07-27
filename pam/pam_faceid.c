/*
 * pam_faceid.so — délègue l'authentification à un daemon de reconnaissance
 * faciale tournant dans la session de l'utilisateur cible (socket Unix).
 *
 * Renvoie :
 *   PAM_SUCCESS           si le daemon répond "OK"
 *   PAM_AUTH_ERR          si le daemon répond "FAIL" (visage non reconnu)
 *   PAM_AUTHINFO_UNAVAIL  si le daemon/la socket est indisponible ou timeout
 *
 * Avec un contrôle "sufficient", AUTH_ERR et AUTHINFO_UNAVAIL laissent PAM
 * passer au module suivant (mot de passe). Impossible de se verrouiller dehors.
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <pwd.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <syslog.h>
#include <errno.h>

#include <security/pam_appl.h>
#include <security/pam_modules.h>

#define SOCK_SUFFIX "/Library/Application Support/faceid/faceid.sock"

/* Without this the module is invisible: the PAM rule is `sufficient`, so every failure
 * silently degrades to the password prompt and the user cannot tell whether the module
 * ran at all. Inspect with:  log show --last 2m --predicate 'sender == "sudo"'
 * or:  syslog -k Sender pam_faceid                                                  */
#define FACEID_LOG(fmt, ...) \
    syslog(LOG_AUTH | LOG_NOTICE, "pam_faceid: " fmt, ##__VA_ARGS__)
/* sudo : large (choix dans le modal + auth). écran verrouillé : court, pour
 * basculer vite sur le mot de passe si le daemon traîne. */
#define RECV_TIMEOUT_SLOW 120
#define RECV_TIMEOUT_FAST 6

static int ask_daemon(const char *home, int fast) {
    char path[1024];
    if (snprintf(path, sizeof(path), "%s%s", home, SOCK_SUFFIX)
            >= (int)sizeof(path))
        return PAM_AUTHINFO_UNAVAIL;

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return PAM_AUTHINFO_UNAVAIL;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    struct timeval tv;
    tv.tv_sec = fast ? RECV_TIMEOUT_FAST : RECV_TIMEOUT_SLOW;
    tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        FACEID_LOG("cannot reach the daemon at %s (%s); falling back to password",
                   path, strerror(errno));
        close(fd);
        return PAM_AUTHINFO_UNAVAIL;
    }

    const char *cmd = fast ? "VERIFY_LOCK\n" : "VERIFY\n";
    size_t clen = strlen(cmd);
    if (write(fd, cmd, clen) != (ssize_t)clen) {
        close(fd);
        return PAM_AUTHINFO_UNAVAIL;
    }

    char buf[16];
    memset(buf, 0, sizeof(buf));
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);

    if (n <= 0) {
        FACEID_LOG("daemon did not answer within %ds; falling back to password",
                   fast ? RECV_TIMEOUT_FAST : RECV_TIMEOUT_SLOW);
        return PAM_AUTHINFO_UNAVAIL;
    }
    if (strncmp(buf, "OK", 2) == 0) {
        FACEID_LOG("face recognised, authenticating");
        return PAM_SUCCESS;
    }
    if (strncmp(buf, "FAIL", 4) == 0) {
        FACEID_LOG("face not recognised; falling back to password");
        return PAM_AUTH_ERR;
    }
    FACEID_LOG("unexpected answer from daemon; falling back to password");
    return PAM_AUTHINFO_UNAVAIL;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags,
                                   int argc, const char **argv) {
    (void)flags;

    /* argument "lock" (dans /etc/pam.d/screensaver) => mode écran verrouillé
     * (échec rapide, pas de modal). */
    int fast = 0;
    for (int i = 0; i < argc; i++)
        if (strcmp(argv[i], "lock") == 0) fast = 1;

    const char *user = NULL;
    if (pam_get_user(pamh, &user, NULL) != PAM_SUCCESS || user == NULL) {
        FACEID_LOG("PAM did not provide a user; falling back to password");
        return PAM_AUTHINFO_UNAVAIL;
    }

    /* The socket lives in the *calling* user's home. If PAM hands us the target account
     * (root) instead, there is nothing to talk to, which is worth seeing in the log. */
    struct passwd *pw = getpwnam(user);
    if (pw == NULL || pw->pw_dir == NULL) {
        FACEID_LOG("no home directory for user '%s'; falling back to password", user);
        return PAM_AUTHINFO_UNAVAIL;
    }

    FACEID_LOG("invoked for user '%s' (home %s)", user, pw->pw_dir);
    return ask_daemon(pw->pw_dir, fast);
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags,
                              int argc, const char **argv) {
    (void)pamh; (void)flags; (void)argc; (void)argv;
    return PAM_SUCCESS;
}
