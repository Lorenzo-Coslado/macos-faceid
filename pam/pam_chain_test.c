/*
 * pam_chain_test — run the "sudo" PAM stack directly and report the outcome.
 *
 * Driving the real sudo(8) is not a usable test: CI runners grant NOPASSWD, so sudo
 * skips authentication entirely and never touches the PAM stack. Calling pam_authenticate
 * against the same service name exercises exactly what sudo would read (/etc/pam.d/sudo,
 * and through it sudo_local), independent of sudoers policy.
 *
 * The conversation function refuses to supply a password, so if the stack falls through
 * to pam_opendirectory we fail rather than hang.
 *
 * Usage: pam_chain_test <username>   ->  exit 0 if authentication succeeded
 */
#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int refuse_conv(int num_msg, const struct pam_message **msg,
                       struct pam_response **resp, void *appdata) {
    (void)msg; (void)appdata;
    if (num_msg <= 0) return PAM_CONV_ERR;
    /* Anything asking for input means our module did not already succeed. */
    *resp = NULL;
    return PAM_CONV_ERR;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <username>\n", argv[0]);
        return 2;
    }

    struct pam_conv conv = { refuse_conv, NULL };
    pam_handle_t *pamh = NULL;

    int rc = pam_start("sudo", argv[1], &conv, &pamh);
    if (rc != PAM_SUCCESS) {
        fprintf(stderr, "pam_start failed: %s\n", pam_strerror(pamh, rc));
        return 2;
    }

    rc = pam_authenticate(pamh, 0);
    printf("pam_authenticate: %d (%s)\n", rc, pam_strerror(pamh, rc));
    pam_end(pamh, rc);

    return rc == PAM_SUCCESS ? 0 : 1;
}
