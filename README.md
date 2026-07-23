<div align="center">

<img src="assets/logo.png" width="118" alt="FaceID" />

# FaceID

**Déverrouille `sudo` avec ton visage.**
App macOS native dans la barre de menus — reconnaissance faciale **100 % locale**,
un panneau de choix natif, et une capsule façon **Dynamic Island** pendant le scan.

<br>

[![CI](https://github.com/Lorenzo-Coslado/macos-faceid/actions/workflows/ci.yml/badge.svg)](https://github.com/Lorenzo-Coslado/macos-faceid/actions/workflows/ci.yml)
&nbsp;![macOS 13+](https://img.shields.io/badge/macOS-13%2B-1d1d1f?logo=apple)
&nbsp;![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-1d1d1f)
&nbsp;![MIT](https://img.shields.io/badge/license-MIT-3ba55d)

<br>

<a href="https://github.com/Lorenzo-Coslado/macos-faceid/releases/latest/download/FaceID.dmg">
  <img src="https://img.shields.io/badge/Download%20for%20macOS-1d1d1f?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS" height="46" />
</a>

<sub>Signée et notarisée par Apple — aucun avertissement Gatekeeper. Tu double-cliques, c'est tout.</sub>

<br><br>

<img src="assets/demo.gif" width="640" alt="Scan Face ID puis déverrouillage" />

</div>

---

## Ce que c'est

Tu tapes `sudo`, la caméra te reconnaît, et c'est déverrouillé — sans mot de passe.
Parti d'un hack de week-end, c'est devenu une vraie petite app : enrôlement guidé,
réglages, choix entre Face ID / Touch ID / mot de passe, le tout empaqueté dans un
`.app` autonome. Rien ne quitte ton Mac, et `sudo` garde **toujours** le mot de passe
en repli : impossible de te bloquer.

> [!IMPORTANT]
> **C'est un projet fun, pas un outil de sécurité.** Une webcam 2D peut être trompée
> par une photo — ce n'est **pas** plus sûr que Touch ID. Garde-le pour le confort du
> terminal, pas pour protéger quoi que ce soit de sensible.

## Aperçu

<table>
<tr>
<td width="50%" valign="top"><img src="assets/onboarding.png" alt="Enrôlement guidé" /></td>
<td width="50%" valign="top"><img src="assets/modal.png" alt="Panneau de choix" /></td>
</tr>
<tr>
<td align="center"><b>Enrôlement guidé</b><br><sub>Ton visage enregistré en quelques secondes.</sub></td>
<td align="center"><b>Face ID · Empreinte · Mot de passe</b><br><sub>Un panneau natif à chaque <code>sudo</code>.</sub></td>
</tr>
</table>

## Installation

1. **[Télécharge `FaceID.dmg`](https://github.com/Lorenzo-Coslado/macos-faceid/releases/latest/download/FaceID.dmg)**, ouvre-le, glisse **FaceID** dans **Applications**.
2. Lance **FaceID** — une petite icône apparaît dans la barre de menus.
3. Clique dessus → **Configurer mon visage** (autorise la caméra).
4. **Réglages → Activer Face ID pour sudo** (ton mot de passe admin, une fois).
5. Teste :
   ```bash
   sudo -k && sudo true
   ```
   La caméra s'allume, te reconnaît, `sudo` passe. ✨

Aucune autre installation : Python, OpenCV et les modèles sont **embarqués dans l'app**.

## Comment ça marche

```
sudo ─▶ module PAM (root) ──socket──▶ daemon (ta session, possède la caméra)
        pam_faceid.so                   └─ YuNet (détection) + SFace (embeddings)
                                             └─ similarité cosinus ▶ OK / FAIL
```

Un process root lancé par `sudo` n'a pas accès à la caméra (bloqué par TCC). Un petit
**module PAM** délègue donc à un **daemon** dans ta session, qui détecte ton visage
([YuNet](https://github.com/opencv/opencv_zoo)), calcule un embedding
([SFace](https://github.com/opencv/opencv_zoo)) et le compare à ton visage enrôlé.
La règle PAM est `sufficient` : en cas d'échec, elle **retombe sur le mot de passe**.

## Sécurité — franchement

- **Anti-spoof faible.** Caméra RGB 2D → une photo peut tromper la reconnaissance.
  C'est pour ça qu'Apple exige un capteur infrarouge (TrueDepth) pour le vrai Face ID.
- **Le mot de passe marche toujours.** Règle `sufficient` : visage raté, daemon coupé
  ou app supprimée → repli mot de passe. Aucun lockout, jamais.
- **Local, point.** Tes embeddings vivent dans `~/Library/Application Support/faceid`
  et ne quittent jamais ta machine. FileVault au démarrage reste au mot de passe.

## Compiler depuis les sources

<details>
<summary>Pour les développeurs</summary>

Prérequis : macOS (Apple Silicon), Xcode Command Line Tools (`xcode-select --install`),
Python 3.12 (`brew install python@3.12`).

```bash
git clone https://github.com/Lorenzo-Coslado/macos-faceid.git
cd macos-faceid
./install.sh                    # venv, deps, modèles, helpers, app (mode dev)
```

Produire le DMG signé + notarisé (nécessite un certificat *Developer ID Application*
et un profil `notarytool` nommé `faceid-notary`) :

```bash
./scripts/build-release.sh
```
</details>

## FAQ

**Ça déverrouille l'écran verrouillé / la session ?**
Non. macOS protège ce chemin (SIP + restrictions Apple sur les plugins d'auth tiers,
confirmé par Apple DTS). Pour le déverrouillage mains-libres, utilise l'**Apple Watch**.
L'exploration complète est dans [`LOCK-SCREEN-PLAN.md`](LOCK-SCREEN-PLAN.md).

**J'aurai un avertissement « développeur non identifié » ?**
Non — la version téléchargée est signée Developer ID et notarisée par Apple.

**Désinstaller ?**
Réglages → désactiver Face ID pour sudo, quitter l'app, jeter `FaceID.app`. Pour
effacer ton visage : `rm -rf ~/Library/Application\ Support/faceid`.

## Licence

[MIT](LICENSE) · fait pour le fun · aucune garantie.
