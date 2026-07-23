# Face ID pour l'écran verrouillé — plan via plugin d'autorisation (voie légitime, SIP‑compatible)

## ✅ RÉSULTATS DE VALIDATION (22 juil.)

Les deux inconnues make‑or‑break sont **levées, positivement** :

- **Phase 1 — chargement + socket** : ✅ le plugin signé se charge dans
  `SecurityAgentHelper-arm64` et **joint le daemon** depuis son bac à sable
  (`faceid-authplugin: MechanismInvoke daemon_reachable=1`), testé via un droit
  de test dédié (zéro risque). Signature/Library Validation OK.
- **Phase 3 — caméra + reco écran verrouillé** : ✅ `VERIFY_LOCK` renvoie `OK`
  **écran verrouillé**, scores 0.79–0.82, 2 visages, `bright≈95`, en ~0.1 s.
  macOS ne coupe PAS la caméra au verrouillage.

➡️ **Aucun blocage technique de fond ne subsiste.** Reste la Phase 2 (plomberie
d'auth : convertir `system.login.screensaver` en `evaluate-mechanisms` + décider
« visage OU mot de passe »), qui est de l'ingénierie délicate mais sans inconnue.



> ⚠️ **Danger réel de blocage total du Mac.** Une erreur dans un plugin d'autorisation ou
> dans la base d'autorisation peut t'empêcher de **déverrouiller OU de te connecter**.
> Aucune étape modifiant l'authentification n'est lancée sans les filets de la Phase 0.
> Apple elle‑même l'écrit : *« if you make a mistake … it's likely that you will not be
> able to log in in order to fix it »* (doc NullAuthPlugin).

## Pourquoi cette voie (et pas PAM)

`/etc/pam.d/screensaver` est **protégé** (fichier d'origine Apple, non modifiable par root — vérifié
sur ta machine : `mv`/écriture → EPERM). De plus `coreauthd` **rejette les modules PAM non signés
au déverrouillage d'écran** (Library Validation). Les **plugins d'autorisation** (`SecurityAgentPlugins`)
sont la seule voie **compatible SIP** documentée par Apple pour intervenir sur `system.login.screensaver`.

## Architecture cible

```
Écran verrouillé
   └─ loginwindow → SecurityAgent évalue le droit  system.login.screensaver
        └─ chaîne de "mechanisms" (séquence)
             ├─ FaceIDAuth:check          ← NOTRE plugin (bundle signé)
             │     └─ se connecte à la socket du daemon → VERIFY_LOCK
             │         ├─ visage reconnu  → satisfait l'auth (déverrouille)
             │         └─ échec/timeout   → laisse la main au mot de passe
             └─ builtin:authenticate      ← saisie mot de passe (repli)
```

Composants :
1. **`FaceIDAuth.bundle`** : plugin d'autorisation en C (API `AuthorizationPluginCreate` + interface
   mécanisme). Installé dans `/Library/Security/SecurityAgentPlugins/`, **root:wheel**, **signé** (ad‑hoc min.).
2. **Daemon Face ID existant** (déjà en place, `VERIFY_LOCK` déjà implémenté, budget 5 s, HUD).
3. **Enregistrement** dans la base d'autorisation via `security authorizationdb`.

## Questions techniques ouvertes (à VALIDER avant d'y croire)

Ces points ne sont pas garantis par la doc — chaque phase en valide un, sur plugin inoffensif d'abord :

1. **Sémantique de court‑circuit.** Est‑ce qu'un mécanisme qui pose `kAuthorizationResultAllow`
   **saute** `builtin:authenticate` (donc déverrouille sans mot de passe) ? Sinon il faut la variante
   « injection d'identifiants » (le mécanisme met `kAuthorizationEnvironmentUsername/Password` dans le
   contexte pour que `builtin:authenticate` réussisse en silence → **implique de stocker le mot de passe**).
   → validé en **Phase 2**.
2. **Bac à sable du plugin.** Le mécanisme tourne dans un contexte restreint
   (`authorizationhost`/`SecurityAgent`). Peut‑il **ouvrir notre socket Unix** vers le daemon ?
   → validé en **Phase 1** (c'est le go/no‑go du projet).
3. **Caméra en écran verrouillé.** macOS peut bloquer la caméra quand l'écran est verrouillé.
   → validé en **Phase 3**.
4. **Signature / Library Validation.** Le bundle et son exécutable doivent être signés (ad‑hoc au
   minimum, universel arm64 idéalement). → traité dès la construction.

## PHASE 0 — Filets anti‑blocage (OBLIGATOIRE, aucune exception)

Rien de risqué ici, mais tout le reste en dépend.

1. **Créer un 2ᵉ compte administrateur** (ex. `secours`) — Réglages Système › Utilisateurs. Ta machine
   n'a qu'un admin (`lorenzo`) : c'est le filet n°1. Depuis ce compte on peut réparer la base d'autorisation.
2. **Activer SSH** pour réparer à distance : `sudo systemsetup -setremotelogin on`.
3. **Sauvegarder la règle par défaut** :
   ```bash
   security authorizationdb read system.login.screensaver > ~/faceid-screensaver-default.plist
   ```
4. **LaunchDaemon d'auto‑réinitialisation au boot** (roues stabilisatrices) : à chaque démarrage,
   remet le droit à sa valeur par défaut **sauf** si un flag « confirmé » existe. Un plugin fautif →
   redémarrage (possible depuis l'écran verrouillé) → droit réinitialisé → déverrouillage mot de passe
   revient. Script installé `/usr/local/lib/faceid/screensaver-reset.sh` :
   ```bash
   #!/bin/bash
   FLAG=/usr/local/lib/faceid/.screensaver-confirmed
   [ -f "$FLAG" ] || /usr/sbin/security authorizationdb write system.login.screensaver \
       authenticate-session-owner-or-admin
   ```
   (chargé par `/Library/LaunchDaemons/com.lorenzo.faceid.ssreset.plist`, `RunAtLoad`.)
5. **Recovery en dernier recours** : la base est `/var/db/auth.db` (SQLite). En Recovery on peut la
   corriger, mais c'est pénible → c'est pourquoi le filet n°4 (reset au boot) est le vrai garde‑fou.

## PHASE 1 — Plugin NULL : valider chargement + accès socket (risque nul pour l'auth)

But : prouver que notre plugin **se charge** dans la chaîne screensaver ET qu'il **peut joindre le daemon**.
Le mécanisme est **observateur** : il logue et pose **toujours `Allow`** (ne change pas l'issue, il est
ajouté à côté de `builtin:authenticate` qui reste seul décideur).

Squelette `FaceIDAuth.c` (6 fonctions imposées par l'API) :
```c
#include <Security/AuthorizationPlugin.h>
static const AuthorizationCallbacks *gCB;

typedef struct { AuthorizationEngineRef engine; } Mech;

static OSStatus MechanismInvoke(AuthorizationMechanismRef m) {
    Mech *me = (Mech*)m;
    // PHASE 1 : test de connexion à la socket du daemon (log uniquement)
    // int fd = socket(AF_UNIX,SOCK_STREAM,0); connect(... faceid.sock ...);
    // write(fd,"PING\n",5); read(...); syslog(LOG_ERR,"faceid: daemon joignable=%d",ok);
    return gCB->SetResult(me->engine, kAuthorizationResultAllow);
}
static OSStatus MechanismCreate(AuthorizationPluginRef p, AuthorizationEngineRef e,
                                AuthorizationMechanismId id, AuthorizationMechanismRef *out){
    Mech *me = calloc(1,sizeof(Mech)); me->engine=e; *out=(AuthorizationMechanismRef)me; return errAuthorizationSuccess;
}
static OSStatus MechanismDeactivate(AuthorizationMechanismRef m){ return gCB->DidDeactivate(((Mech*)m)->engine); }
static OSStatus MechanismDestroy(AuthorizationMechanismRef m){ free(m); return errAuthorizationSuccess; }
static OSStatus PluginDestroy(AuthorizationPluginRef p){ return errAuthorizationSuccess; }

static const AuthorizationPluginInterface gPI = {
    kAuthorizationPluginInterfaceVersion, PluginDestroy,
    MechanismCreate, MechanismInvoke, MechanismDeactivate, MechanismDestroy };

OSStatus AuthorizationPluginCreate(const AuthorizationCallbacks *cb, AuthorizationPluginRef *outP,
                                   const AuthorizationPluginInterface **outPI){
    gCB=cb; *outP=(AuthorizationPluginRef)&gPI; *outPI=&gPI; return errAuthorizationSuccess;
}
```
Build + signature + install :
```bash
mkdir -p FaceIDAuth.bundle/Contents/MacOS
# Info.plist (CFBundleIdentifier com.lorenzo.FaceIDAuth, CFBundleExecutable FaceIDAuth)
clang -bundle -o FaceIDAuth.bundle/Contents/MacOS/FaceIDAuth FaceIDAuth.c -framework Security
codesign --force --sign - FaceIDAuth.bundle
sudo cp -R FaceIDAuth.bundle /Library/Security/SecurityAgentPlugins/
sudo chown -R root:wheel /Library/Security/SecurityAgentPlugins/FaceIDAuth.bundle
```
Enregistrement (mécanisme AJOUTÉ avant `builtin:authenticate`, observateur) :
```bash
security authorizationdb read system.login.screensaver > /tmp/ss.plist
cp /tmp/ss.plist ~/faceid-screensaver-default.plist            # backup
# insérer "FaceIDAuth:check" juste avant la ligne builtin:authenticate
/usr/libexec/PlistBuddy -c "Add :mechanisms:0 string FaceIDAuth:check" /tmp/ss.plist
sudo security authorizationdb write system.login.screensaver < /tmp/ss.plist
```
Validation : verrouiller, déverrouiller au **mot de passe** (rien ne doit changer), puis :
```bash
log show --last 2m --predicate 'process=="SecurityAgent" OR eventMessage CONTAINS "faceid"' | grep faceid
```
- Si on voit « daemon joignable=1 » → **feu vert, le projet est faisable**.
- Si le plugin ne charge pas, ou ne peut pas ouvrir la socket → **stop**, le bac à sable bloque
  (il faudrait alors un canal XPC Mach au lieu d'une socket Unix — rallonge notable).

## PHASE 2 — Court‑circuit conditionnel (valider « visage → déverrouille sans mot de passe »)

Le mécanisme pose `Allow` **seulement** sur une condition simulée (ex. présence d'un fichier témoin),
et on observe si le mot de passe est **sauté** ou **toujours demandé**.
- **Sauté** → modèle « sufficient » OK, on garde `[FaceIDAuth:check, builtin:authenticate]`.
- **Toujours demandé** → passer au modèle **injection** : sur match, poser
  `kAuthorizationContextFlagSticky` + `username`/`password` dans le contexte via `SetContextValue`,
  pour que `builtin:authenticate` réussisse en silence. ⇒ nécessite de **stocker le mot de passe**
  (Keychain système accessible au plugin privilégié) — compromis de sécurité à acter explicitement.

## PHASE 3 — Vraie reconnaissance + caméra verrouillée

Remplacer la condition simulée par un appel réel `VERIFY_LOCK` au daemon (déjà prêt), timeout **dur 4 s**
(sinon risque du « blocage 17 min » documenté). Tester si la **caméra fonctionne écran verrouillé**.
Si macOS la bloque → repli mot de passe (grâce au design). Afficher le HUD Dynamic Island si visible.

## PHASE 4 — Robustesse

- **Survie aux mises à jour** : macOS **réinitialise** la base d'autorisation aux updates → un agent
  ré‑applique le mécanisme après update (et vérifie la version d'OS).
- **Mode confirmé** : après un test concluant, poser le flag pour désactiver le reset‑au‑boot.
- **Désinstallation propre** : `security authorizationdb write system.login.screensaver
  < ~/faceid-screensaver-default.plist` + retrait du bundle + du LaunchDaemon.

## Estimation honnête

- **Effort** : bien supérieur à tout ce qu'on a fait (C bas niveau, base d'autorisation, signature, debug
  quasi‑aveugle via `log show`).
- **Risque** : élevé (blocage possible) — d'où Phase 0 non négociable.
- **Go/No‑Go réel** : la **Phase 1** (le plugin peut‑il joindre le daemon depuis son bac à sable ?).
  Tant qu'on n'a pas ce « oui », le reste est hypothétique.

## Sources

- Apple — NullAuthPlugin (structure, install, avertissement lockout) :
  https://developer.apple.com/library/archive/samplecode/NullAuthPlugin/Listings/Read_Me_About_NullAuthPlugin_txt.html
- Elliot Jordan — Managing login mechanisms in the authorization database (commandes exactes) :
  https://www.elliotjordan.com/posts/macos-authdb-mechs/
- scriptingosx — Demystifying root Part 4: the Authorization Database :
  https://scriptingosx.com/2018/05/demystifying-root-on-macos-part-4-the-authorization-database/
- Apple Developer Forums — Custom Authorization Plugin (SIP‑compatible, MCXSecurityAgent) :
  https://developer.apple.com/forums/thread/760516
- Apple Developer Forums — module PAM rejeté après déverrouillage screensaver (coreauthd) :
  https://developer.apple.com/forums/thread/772227
- openai/codex #29616 — plugin d'auth → blocage écran verrouillé 17 min (mise en garde timeout) :
  https://github.com/openai/codex/issues/29616
- twocanoes/XCreds — plugin d'autorisation open source de référence :
  https://github.com/twocanoes/xcreds
