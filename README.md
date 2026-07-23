# FaceID pour Mac 👁️

Déverrouille `sudo` **avec ton visage** sur macOS — reconnaissance faciale locale,
app dans la barre de menus, panneau de choix natif et petite capsule animée façon
Dynamic Island pendant le scan.

> ⚠️ **Projet fun, pas un produit de sécurité.** Une webcam 2D peut être trompée
> par une photo — ce n'est **pas** plus sûr que Touch ID ou qu'un mot de passe.
> C'est un gadget sympa pour le terminal. `sudo` garde **toujours** le mot de passe
> en repli : tu ne peux pas te bloquer.

## Ce que ça fait

- 🧠 **Face ID pour `sudo`** : tu tapes `sudo`, la caméra te reconnaît, pas de mot de passe.
- 🎛️ **App menu bar native** (Swift/SwiftUI) : enrôlement guidé, réglages, activation en un clic.
- 🪄 **Panneau de choix** Face ID / Empreinte (Touch ID) / Mot de passe.
- ✨ **Capsule « Dynamic Island »** animée pendant le scan (→ ✅ à la reconnaissance).
- 🌍 **11 langues** (s'adapte à la langue du système, anglais par défaut).
- 🔒 **100 % local** : rien ne quitte ton Mac. Repli mot de passe garanti.

Reconnaissance : détection **YuNet** + embeddings **SFace** (OpenCV), comparaison par
similarité cosinus. Le module PAM (`pam_faceid`) délègue à un daemon qui, lui, a la
caméra — parce qu'un process root lancé par `sudo` n'y a pas accès (TCC).

## Prérequis

- macOS (Apple Silicon), une webcam
- **Xcode Command Line Tools** : `xcode-select --install`
- **Python 3.12** : `brew install python@3.12`

## Installation

```bash
git clone https://github.com/Lorenzo-Coslado/macos-faceid.git
cd macos-faceid
./install.sh
```

`install.sh` crée un environnement Python isolé, télécharge les modèles, compile les
composants natifs, construit **FaceID.app** (signée ad-hoc) et l'installe dans
`/Applications`. Comme tu compiles toi-même, pas de blocage Gatekeeper.

Ensuite, dans l'app (icône dans la barre de menus) :
1. **Configurer mon visage** → enrôle ton visage (autorise la caméra quand demandé).
2. **Réglages → Activer Face ID pour sudo** (demande ton mot de passe admin).
3. Teste dans un terminal :
   ```bash
   sudo -k && sudo true
   ```

## Sécurité — à lire

- **Anti-spoof faible** : webcam RGB 2D → une photo peut tromper la reconnaissance.
  C'est pourquoi Apple exige un capteur IR (TrueDepth) pour Face ID.
- La règle PAM est `sufficient` : si le visage échoue ou si le daemon est absent,
  `sudo` **retombe sur le mot de passe**. Aucun risque de lockout.
- FileVault au démarrage reste au mot de passe. Traite ça comme un gadget, garde
  Touch ID / mot de passe comme vraie sécurité.

## Désinstallation

```bash
bash scripts/uninstall.sh          # retire le module PAM, restaure Touch ID
# puis, dans l'app : Quitter ; et jette /Applications/FaceID.app
```

## Écran verrouillé ? Non.

Déverrouiller l'**écran verrouillé** au visage n'est **pas possible** proprement :
macOS protège le fichier PAM `screensaver` (SIP) et interdit aux plugins tiers de
s'y greffer sans perdre Touch ID ni l'UI native (confirmé par Apple DTS). L'exploration
complète est documentée dans [`LOCK-SCREEN-PLAN.md`](LOCK-SCREEN-PLAN.md). Pour ça,
utilise l'**Apple Watch** (natif, sûr).

## Licence

MIT — voir [LICENSE](LICENSE). Fait pour le fun. Aucune garantie.
