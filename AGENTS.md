# Mugshot

## Exploration et vérification

Commencer par les fichiers concernés, élargir selon les résultats. Filtrer les logs.
Vérifier les changements sensibles, puis indiquer les contrôles et leurs limites.

## Builds et autorisations macOS

Utiliser `scripts/local-signing.py` pour signer les builds locaux avec l'identité
persistante du trousseau dédié. Préparer l'app hors d'Applications et l'installer
avec le package vérifié ; conserver les modifications visuelles déjà présentes.

Une signature ad hoc du bundle change son identité à chaque modification de
ressource et invalide Accessibilité, la caméra et les ACL du trousseau. Ne pas
resigner l'app installée avec `codesign --sign -` ni remplacer son certificat.
Si l'identité persistante manque, restaurer son trousseau plutôt que la régénérer.

Pour une modification de pastille, de helper, de ressources ou de packaging :
utiliser les scripts de build, vérifier la signature complète et exécuter
`python3 tests/test_signing_identity.py`. Deux builds différents doivent satisfaire
la même exigence de signature ; des ressources modifiées sans signature doivent
être refusées. Ne pas annoncer une réparation sur la seule base des tests simulés :
vérifier aussi la version et les droits du processus réellement installé.
