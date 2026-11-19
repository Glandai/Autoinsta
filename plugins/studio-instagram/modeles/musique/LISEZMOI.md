# Bibliothèque libre de droits (facultative)

Normalement, la musique des Reels vient de la bibliothèque Instagram (API Audio, route Facebook) et n'a pas besoin de fichier ici.

Ce dossier sert seulement si l'API Audio n'est pas disponible (route Instagram) : déposez-y des pistes dont la licence autorise l'usage sur Instagram (achetées sur Artlist, Epidemic Sound, ou libres comme certaines pistes de Pixabay Music, en vérifiant la licence), au format `.mp3` ou `.m4a`.

Décrivez chaque piste dans `catalogue.yaml` pour que le studio puisse choisir :

```yaml
pistes:
  - fichier: musique/piano-lent.mp3
    titre: "Piano lent"
    ambiance: "intime, lumineux"
    instrumentation: "piano seul"
    tempo: lent
    licence: "Artlist, licence personnelle"
```

Le studio intègre alors la piste à la vidéo (mode `integree`), avec un fondu au début et à la fin.
