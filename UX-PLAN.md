# Plan de simplification — Mugshot

Analyse de l'app telle qu'elle est aujourd'hui (1.0.3), et plan pour la rendre plus
simple à installer et plus évidente à utiliser. Les chiffres sont mesurés sur
`dist/Mugshot.app` du 27 juillet.

---

## 1. Diagnostic

### 1.1 Installation

**Poids : 99 Mo de DMG, 189 Mo installés**, pour un moteur qui tient en 80 lignes de
calcul réel (`faceid/recognizer.py`). Répartition mesurée :

| Composant | Taille |
|---|---|
| `cv2` (dont ~75 Mo de codecs vidéo) | 120 Mo |
| Modèle SFace fp32 | 37 Mo |
| Python.framework + numpy + stdlib | 21 Mo |
| Sparkle | 3 Mo |
| App Swift + helpers + PAM | < 1 Mo |

Les 75 Mo de codecs (`libavcodec` 9,8 Mo, `libx265` 4,7 Mo, `libaom` 3,7 Mo,
`libSvtAv1Enc` 3 Mo, `libcrypto`…) ne servent à rien : le moteur n'appelle que
`cv2.VideoCapture`, `cv2.FaceDetectorYN`, `cv2.FaceRecognizerSF` et `cv2.imwrite`.

**L'activation de sudo demande trois allers-retours.** En lisant
[SettingsView.swift:155](menubar/SettingsView.swift:155) : l'utilisateur bascule
l'interrupteur → `ensureRegistered()` renvoie `.needsApproval` → macOS ouvre les Éléments
d'ouverture → une ligne de texte gris dit « approuvez puis rebasculez » → il rebascule →
le helper échoue en « not permitted » → une alerte l'envoie dans l'Accès complet au
disque → il rebascule une troisième fois. À chaque échec l'interrupteur revient
visuellement à zéro (`finishSudo` relit `Status.sudoActive`), sans état de progression,
sans reprise automatique, sans détection que l'approbation vient d'être donnée.

**Aucune désinstallation depuis l'app.** Le README dit « mettez `Mugshot.app` à la
corbeille ». Restent alors en place : `/usr/local/lib/pam/pam_faceid.so`, la ligne dans
`/etc/pam.d/sudo_local`, l'enregistrement SMAppService du helper, l'élément d'ouverture,
`~/Library/Application Support/faceid` — **et surtout la ligne `pam_tid.so` commentée
dans `/etc/pam.d/sudo`** ([pam-install-root.sh:73](scripts/pam-install-root.sh:73)) :
supprimer l'app laisse Touch ID système désactivé pour sudo, définitivement.
`scripts/uninstall.sh` fait le nettoyage mais n'est pas embarqué dans le bundle et exige
un terminal.

**Le premier lancement commence par un reproche.**
`warnIfRunningFromAnUnstableLocation` ([FaceIDApp.swift:123](menubar/FaceIDApp.swift:123))
affiche une alerte expliquant que l'app est au mauvais endroit, avec un bouton « Montre-moi ».
La convention macOS est de proposer « Déplacer vers Applications » et de le faire.

**Le seul outil de dépannage n'est pas livré.** `scripts/diagnose.sh` répond exactement à
la question « pourquoi sudo ne me demande pas mon visage ? », mais
[build-standalone.sh:99](scripts/build-standalone.sh:99) ne copie que
`pam-install-root.sh` et `pam-uninstall-root.sh` dans le bundle. Il faut cloner le dépôt
pour y accéder.

### 1.2 Usage

**Le modal de choix à chaque `sudo` annule le bénéfice de l'app.** Le produit existe pour
supprimer une friction (taper un mot de passe) et en ajoute une (cliquer un bouton). Il
est activé par défaut (`MODAL_ENABLED`, [config.py:28](faceid/config.py:28)) et
`FACEID_MODAL=0` est décrit comme « l'ancien comportement » alors que c'est le
comportement souhaitable.

**Vocabulaire d'ingénieur dans l'interface.** « Daemon running », « Start Daemon »,
« Stop Daemon », « Adds the PAM module », et une sensibilité exposée comme une similarité
cosinus brute entre 0,30 et 0,50. L'en-tête du menu et le titre des réglages disent
encore « FaceID » alors que l'app s'appelle Mugshot
([FaceIDApp.swift:49](menubar/FaceIDApp.swift:49), `set.title`).

**Le service meurt avec l'app.** `DaemonController` lance le moteur comme processus
enfant et `applicationWillTerminate` le tue. Quitter Mugshot fait retomber `sudo` sur le
mot de passe sans le moindre signe. Et le menu propose littéralement « Arrêter le
service », qui produit ce résultat sur un clic.

**Du français fuit dans l'interface anglaise.** `enroll.py` émet
`msg="pas assez d'échantillons"` et `msg="interrompu"` ([enroll.py:80](faceid/enroll.py:80),
[:86](faceid/enroll.py:86)), affichés tels quels par l'écran d'échec de l'onboarding. Le
dialogue de repli `osascript` est intégralement en français
([daemon.py:53](faceid/daemon.py:53)), tout comme l'invite Touch ID « Déverrouiller sudo »
([daemon.py:222](faceid/daemon.py:222)). Onze langues sont traduites côté Swift, et le
moteur parle français à tout le monde.

**Le curseur de sensibilité redémarre le moteur à chaque pixel.**
`Slider(value: $settings.threshold.onChange(applyDaemon))`
([SettingsView.swift:120](menubar/SettingsView.swift:120)) appelle `restartDaemon()` en
continu pendant le glissement. Chaque appel fait `stop()` puis programme un `start()` à
+0,3 s : un glissement lance une dizaine de processus Python qui se disputent la même
socket. C'est un bug, pas seulement une maladresse.

**Aucun statut agrégé.** L'app connaît `Status.enrolled` et `Status.sudoActive` mais ne
dit jamais « tout est prêt » ni « il manque ceci ». La synthèse existe — dans
`diagnose.sh`, en ligne de commande.

**Le test de reconnaissance passe par `NSUserNotification`**
([FaceIDApp.swift:278](menubar/FaceIDApp.swift:278)), API dépréciée depuis 10.14 et
silencieuse si les notifications ne sont pas autorisées. Il n'affiche ni score ni raison
d'échec, alors que le moteur les calcule (`best=… frames=… faces=… bright=…`).

**Latence.** La caméra est ouverte à froid à chaque vérification et 8 frames sont jetées
en warmup ; le commentaire de [config.py:62](faceid/config.py:62) reconnaît 1,5 à 2 s
avant la première frame exploitable, sur un budget de 8 s.

**Un seul visage, écrasé à chaque fois.** Pas de « ajouter une apparence » (lunettes,
barbe, lumière du soir), là où le vrai Face ID enrôle des apparences supplémentaires.

---

## 2. Ce qui est appliqué

Livré dans cette passe, en plus des phases 0 et 3A.

**Ouvrir l'app ouvre une fenêtre.** C'était le défaut le plus visible : lancer Mugshot
posait une icône dans la barre de menus et n'affichait rien, et recliquer sur l'app ne
produisait *rien du tout* — `applicationShouldHandleReopen` n'était pas implémenté.
Désormais la fenêtre principale s'ouvre au lancement et au reclic. Elle ne s'ouvre pas
quand c'est macOS qui lance l'app à l'ouverture de session, distinction faite avec
`NSApplication.launchIsDefaultUserInfoKey`.

**Une fenêtre qui répond d'abord à « est-ce que ça marche ? ».** Un bandeau en haut donne
l'état en une phrase — *Prêt* / *Aucun visage enregistré* / *Pas encore activé pour sudo* —
et porte le bouton qui règle précisément ce qui manque. L'ancienne fenêtre alignait des
réglages sans jamais dire si l'ensemble fonctionnait.

**Les trois autorisations, d'un seul tenant** (`menubar/SetupFlow.swift`,
`menubar/SetupSheet.swift`). Liste visible dès le départ, chaque ligne se coche seule dès
que l'accord est donné, avec sondage borné à trois minutes plutôt qu'une attente infinie.
Nouvelle méthode XPC `checkAccess` : le helper *demande* s'il peut écrire dans
`/etc/pam.d` en créant puis effaçant un témoin, au lieu de le découvrir en échouant au
milieu de l'installation.

**Sensibilité en trois crans** — Tolérant / Équilibré / Strict, chacun expliqué en une
phrase, la similarité cosinus brute reléguée sous « Avancé ».

**Le test dit ce qu'il a vu.** Il passait par `NSUserNotification` (dépréciée, muette si
les notifications ne sont pas autorisées) et n'annonçait qu'un verdict. Le résultat
s'affiche maintenant dans la fenêtre avec le score, le nombre de visages détectés et la
luminosité — ce que le moteur calculait déjà et jetait.

**Le menu parle de Face ID, plus de démons.** « Daemon running » → *Prêt* / *Aucun visage
enregistré* / *Pas activé pour sudo*. « Arrêter le service », qui coupait sudo d'un clic
sans le dire, est remplacé par « Relancer Face ID », proposé uniquement quand c'est
arrêté. « Ouvrir Mugshot » passe en tête.

**« Copier le diagnostic »** dans la fenêtre, et `diagnose.sh` enfin embarqué dans le
bundle — il fallait cloner le dépôt pour l'obtenir.

## 3. Plan

Quatre phases, ordonnées par rapport bénéfice/coût. Chacune est livrable seule.

### Phase 0 — Ce qui ne coûte rien — **faite**

| # | Action | État |
|---|---|---|
| 0.1 | Le moteur émet des codes (`not-enough-samples`, `interrupted`, `camera-unavailable`, `models-missing`), l'app traduit via `err.<code>` | fait |
| 0.2 | Les invites du moteur passent par `i18n/engine.json`, généré depuis la même table que l'app. `auth-modal` reçoit ses libellés en arguments : il ne connaissait que l'anglais et le français pour une app traduite en onze langues | fait |
| 0.3 | Seuil appliqué au relâchement du curseur, et `restartDaemon()` sérialisé (le démarrage en attente est annulé) | fait |
| 0.4 | « FaceID » → « Mugshot » partout. Au passage, `set.behavior.camera` était défini deux fois et la seconde écrasait la première : le sélecteur de caméra s'intitulait « Réglages caméra système… » | fait |
| 0.5 | `diagnose.sh` embarqué dans le bundle + bouton « Copier le diagnostic » | fait |
| 0.6 | `NSUserNotification` retiré : résultat du test dans la fenêtre, erreur de démarrage en alerte | fait |

### Phase 1 — Condenser les validations macOS

C'est la question centrale, alors commençons par ce qui est **irréductible**. Pour
brancher Face ID sur `sudo`, macOS impose trois accords distincts, et aucun n'est un
choix de l'app :

| Autorisation | Pourquoi macOS l'exige | Contournable depuis l'app ? |
|---|---|---|
| Caméra (TCC) | Toute lecture de webcam | Non — et c'est un dialogue que l'utilisateur attend |
| Éléments d'ouverture | `SMAppService` enregistre un LaunchDaemon root depuis un bundle | Non |
| Accès complet au disque | `/etc/pam.d` est protégé ; le daemon root doit y écrire | Non |

Donc, à mode de distribution constant, **on ne peut pas descendre en dessous de trois**.
Ce qu'on peut supprimer, c'est la *sensation* de trois échecs successifs — et c'est fait
(voir « Ce qui est appliqué » plus bas) : les trois étapes sont affichées d'emblée,
chacune se coche seule quand l'utilisateur revient des Réglages système, et il ne
rebascule plus jamais un interrupteur déjà basculé.

**1.1 La vraie condensation : livrer un `.pkg` plutôt qu'un `.dmg`.** Là on passe de
trois accords à **un seul mot de passe**.

Un paquet signé et notarisé est installé par l'Installeur système, qui s'exécute en root
avec les droits nécessaires et n'est pas soumis aux mêmes restrictions TCC. Son script
`postinstall` peut, en une seule authentification (le dialogue « L'Installeur souhaite
apporter des modifications ») :

* poser `Mugshot.app` dans `/Applications` — plus de glisser-déposer, plus d'app lancée
  depuis l'image disque, donc plus d'alerte « déplacez-moi » ;
* installer `pam_faceid.so` dans `/usr/local/lib/pam` ;
* écrire `/etc/pam.d/sudo_local` et ajouter l'`include` manquant dans `/etc/pam.d/sudo`.

Il ne reste alors qu'un dialogue caméra au premier enrôlement. Bilan : **3 autorisations
+ un glisser-déposer → 1 mot de passe + 1 dialogue caméra.**

Points à traiter avant de s'engager :

* Le daemon privilégié reste nécessaire pour *désactiver* plus tard. Il ne serait plus
  enregistré qu'au moment où l'utilisateur désactive — c'est-à-dire presque jamais.
  L'installation courante ne verrait plus ni Éléments d'ouverture, ni Accès complet au
  disque.
* Sparkle sait installer une mise à jour livrée en paquet
  (`sparkle:installationType="package"`), donc l'auto-update survit.
* Un paquet qui touche `/etc/pam.d` doit être irréprochable : `postinstall` idempotent,
  sauvegarde préalable, et un `preinstall` qui refuse d'agir si `/etc/pam.d/sudo` n'a pas
  la forme attendue. Le script `pam-install-root.sh` actuel fait déjà ces vérifications
  et se réutilise tel quel.
* Un `.pkg` désinstalle moins naturellement qu'une app qu'on jette à la corbeille : il
  faut livrer la désinstallation dans l'app (point 1.4), qui manque de toute façon.

**1.2 Se déplacer soi-même** — sans objet si l'on part sur le `.pkg`. Sinon : au premier
lancement hors de `/Applications`, proposer « Déplacer vers Applications » et faire la
copie puis relancer, au lieu d'expliquer le problème à l'utilisateur.

**1.3 Chaîner l'onboarding.** *Fait.* L'écran de fin d'enrôlement disait « vous pouvez
maintenant activer Face ID pour sudo dans les réglages » et laissait chercher ; il ouvre
maintenant la fenêtre principale, dont le bandeau porte le bouton qui active.

**1.4 Désinstallation depuis l'app.** Réglages → « Supprimer Mugshot » : retirer la règle
PAM, **réactiver `pam_tid.so`**, désenregistrer le helper et l'élément d'ouverture,
proposer d'effacer les embeddings, puis mettre l'app à la corbeille. C'est le portage en
Swift de `scripts/uninstall.sh`, qui devient accessible sans terminal. Corrige au passage
la désactivation permanente de Touch ID système décrite en 1.1 du diagnostic.

### Phase 2 — L'usage devient invisible (≈ 3–4 jours)

**2.1 Supprimer le modal par défaut.** Basculer `MODAL_ENABLED` à `0` : `sudo` lance
directement le scan avec le HUD. Le HUD porte les échappatoires — Échap ou clic → mot de
passe, ⌘F → empreinte. Le panneau à trois boutons devient une option pour ceux qui le
veulent.

**2.2 Le service survit à l'app.** Installer le LaunchAgent déjà écrit
(`launchagent/com.lorenzo.faceid.plist`) avec `KeepAlive`, au lieu de lancer le moteur en
processus enfant. Le menu perd « Démarrer / Arrêter le service » et gagne un unique
interrupteur « Face ID actif ».

**2.3 Raccourcir le démarrage à froid.** Le warmup fixe de 8 frames est un compromis
aveugle. Le remplacer par un warmup adaptatif (avancer dès que la luminosité se
stabilise), forcer le backend `cv2.CAP_AVFOUNDATION`, et demander 640×480 plutôt que la
résolution native. *Ne pas* garder la caméra ouverte entre deux vérifications : la LED
verte resterait allumée, ce qui est pire que 1,5 s d'attente.

**2.4 Un statut, pas des symptômes.** Porter la logique de `diagnose.sh` en Swift et
l'afficher en haut des réglages : soit « Prêt », soit la première chose qui manque avec
le bouton qui la répare.

**2.5 Sensibilité en trois crans.** Tolérant / Équilibré / Strict → 0,33 / 0,36 / 0,42.
La valeur brute reste accessible sous un dépliant.

**2.6 Test de reconnaissance utile.** Une petite fenêtre avec le résultat, le score et la
raison de l'échec (le moteur renvoie déjà `best=… faces=… bright=…`), à la place de la
notification silencieuse.

**2.7 Plusieurs apparences.** `embeddings.npy` devient un jeu d'apparences nommées.
« Ajouter une apparence » à côté de « Ré-enregistrer », comme le vrai Face ID.

### Phase 3 — Le poids

**Option A — dégraissage. Fait, et le gain est plus faible qu'annoncé : 189 → 175 Mo
installés, 94,3 → 89,0 Mo à télécharger.**
Ce qui a été appliqué : `opencv-python-headless` à la place de `opencv-contrib-python`
(les classes `FaceDetectorYN` et `FaceRecognizerSF` sont dans le module principal),
suppression des cascades Haar de `cv2/data` (9 Mo, jamais utilisées — la détection passe
par YuNet), `strip` des symboles, et exclusion d'une quinzaine de modules stdlib.

Au passage, `packaging/faceid.spec` était **régénéré à chaque build** par
`--specpath packaging` puis supprimé : aucun réglage qu'il contenait n'était appliqué.
`build-standalone.sh` l'utilise désormais tel quel.

**Pourquoi seulement −14 Mo.** J'avais estimé −60 % sans vérifier la structure du wheel.
`cv2.abi3.so` déclare `libavcodec`, `libavformat`, `libavutil`, `libswscale` et
`libavdevice` en dépendances de chargement (`otool -L`). Ces bibliothèques et leur
fermeture transitive — x265, aom, SvtAv1Enc, vpx, environ 70 Mo — ne peuvent pas être
retirées du bundle : sans elles, `import cv2` échoue. Le moteur ne décode pourtant aucune
vidéo, il lit des frames de webcam via AVFoundation. C'est un coût structurel du wheel
OpenCV, pas un surplus qu'on peut élaguer.

Restent donc deux leviers réels, tous deux hors du périmètre « une journée » :

* **Modèle SFace int8** (9,9 Mo contre 38,7 Mo, soit −29 Mo). Téléchargé et vérifié
  disponible dans OpenCV Zoo. **Non appliqué**, et délibérément : la quantification
  déplace l'espace des embeddings. Les `embeddings.npy` déjà enrôlés cesseraient de
  correspondre, et comme la règle PAM est `sufficient`, l'échec serait silencieux —
  l'utilisateur retomberait sur son mot de passe sans explication. Il faut d'abord
  mesurer la similarité fp32↔int8 sur des visages réels, retarifer le seuil, et forcer
  un ré-enrôlement à la mise à jour. Je n'avais pas d'échantillon de visage pour
  trancher, et je n'ai pas allumé la caméra pour en produire un.
* **OpenCV compilé sur mesure** (modules `objdetect` + `dnn` + `videoio/AVFoundation`
  seulement), ce qui supprimerait les 70 Mo de codecs. Chantier de plusieurs jours, à
  mettre en balance avec l'option B qui règle le problème par disparition.

**Option B — moteur natif (1 à 2 semaines, −95 %).** Réécrire le moteur en Swift :
AVFoundation pour la capture, Core ML pour YuNet et SFace convertis en `.mlpackage`.
Disparaissent : Python, PyInstaller, le venv, `requirements.txt`,
`scripts/download-models.sh`, `scripts/setup-python.sh`, et la moitié des 40 scripts.
Le DMG tombe à 8–12 Mo, le démarrage devient instantané, et tout le projet parle un seul
langage. Le seul morceau non trivial est de reproduire `alignCrop` — une transformation
de similarité sur 5 points de repère, que Vision fournit.

Recommandation : faire A immédiatement, viser B.

### Phase 4 — Le dépôt (≈ 1 jour)

- 40 scripts dans `scripts/` pour un projet de cette taille. En regrouper l'essentiel
  derrière `make setup | build | release | diagnose`.
- `install.sh` est en français alors que tout le reste du projet est en anglais.
- Reste de l'ancienne marque à supprimer : `assets/FaceID.icns`, `build/FaceID.app`,
  `dist/FaceID.dmg`, `authplugin/FaceIDAuth` (binaire compilé versionné).
- `mugshot-sparkle-private-key.txt` est bien couvert par `.gitignore` — le laisser à la
  racine reste une invitation à l'accident, le déplacer dans le trousseau.

---

## 4. Reste à faire, par ordre conseillé

| Ordre | Lot | Effet ressenti | Coût |
|---|---|---|---|
| 1 | 1.1 — distribution en `.pkg` | 3 autorisations + glisser-déposer → 1 mot de passe | 2–3 j |
| 2 | 1.4 — désinstallation dans l'app | Répare la désactivation permanente de Touch ID système | 1 j |
| 3 | Phase 2 | `sudo` déverrouille sans clic ; le service survit à l'app | 3–4 j |
| 4 | Phase 4 | Le dépôt redevient lisible | 1 j |
| 5 | SFace int8 | −29 Mo, une fois la compatibilité mesurée | 1 j + validation |
| 6 | Phase 3 option B | Le projet perd sa moitié Python, et les 70 Mo de codecs avec | 1–2 sem |

Une contrainte d'ordre : 2.2 (LaunchAgent) doit passer avant 2.1 (suppression du modal),
sinon un `sudo` sans modal face à un service arrêté échoue sans rien afficher.

Et une remarque sur la 1.1 : si le `.pkg` est retenu, 1.2 (auto-déplacement vers
Applications) et l'alerte « déplacez-moi » disparaissent d'elles-mêmes, puisque
l'installeur pose l'app au bon endroit. C'est le genre de simplification qui en supprime
d'autres plutôt que d'en ajouter.
