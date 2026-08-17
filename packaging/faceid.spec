# -*- mode: python ; coding: utf-8 -*-
"""Empaquetage du moteur Python autonome.
Construire avec :  pyinstaller packaging/faceid.spec

Ce fichier était auparavant régénéré à chaque build (`--specpath packaging`) puis jeté,
donc les réglages ci-dessous ne s'appliquaient jamais. `build-standalone.sh` l'utilise
maintenant tel quel.
"""
import os

ROOT = os.path.dirname(SPECPATH)          # noqa: F821 — fourni par PyInstaller

# Modules jamais importés par le moteur (il n'utilise que cv2 + numpy + la stdlib).
# Chacun tire des dizaines de mégaoctets par transitivité.
EXCLUDED_MODULES = [
    "tkinter", "unittest", "pydoc", "doctest", "pdb",
    "test", "lib2to3", "distutils", "setuptools", "pip",
    "curses", "sqlite3", "xmlrpc", "ftplib", "imaplib", "smtplib",
    "matplotlib", "PIL", "pandas", "scipy",
]

# Fichiers de données inutiles embarqués par cv2 : `data/` contient les cascades Haar
# (~9 Mo), un détecteur historique que le moteur n'utilise pas — il détecte avec YuNet.
def keep_datum(dest):
    unwanted = ("cv2/data/", "cv2\\data\\")
    return not any(part in dest for part in unwanted)


a = Analysis(
    [os.path.join(SPECPATH, "faceid_entry.py")],   # noqa: F821
    pathex=[ROOT],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=EXCLUDED_MODULES,
    noarchive=False,
    optimize=0,
)
a.datas = [d for d in a.datas if keep_datum(d[0])]

pyz = PYZ(a.pure)                                   # noqa: F821

exe = EXE(                                          # noqa: F821
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='faceid',
    debug=False,
    bootloader_ignore_signals=False,
    # Retire les tables de symboles : ~120 Mo de dylibs OpenCV en sortent allégés, et
    # la signature est calculée après, dans build-standalone.sh.
    strip=True,
    # UPX désactivé volontairement : un binaire compressé par UPX casse la signature
    # de code et la notarisation sur macOS.
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(                                     # noqa: F821
    exe,
    a.binaries,
    a.datas,
    strip=True,
    upx=False,
    upx_exclude=[],
    name='faceid',
)
