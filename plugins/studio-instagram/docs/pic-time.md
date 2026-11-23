# Pic-Time : comment le studio lit les galeries

Pic-Time n'a pas d'API publique (seulement Zapier, pour créer des galeries ou suivre des commandes). Le studio lit donc une galerie comme le fait un navigateur, à partir de son **lien de partage**.

## Le lien à donner

Dans Pic-Time, ouvre la galerie, puis **Partager** et copie le lien d'accès direct. Il ressemble à :

```
https://tonstudio.pic-time.com/client/nom-de-la-galerie/gallery?sectoken2=AAAA…
```

Le paramètre `sectoken2` donne l'accès sans code ni inscription. Le portfolio de l'espace Pic-Time est protégé par un code d'accès : le studio ne l'utilise pas et ne le demande jamais ; il travaille galerie par galerie, avec ces liens.

Vérification : `./studio pictime analyser-lien "<lien>"` affiche le titre, le nombre de photos, les scènes et les photos mises en avant.

## Ce que le studio en tire

Pour chaque galerie, le studio lit le manifeste public de la galerie (fichier `gallery.json.txt` sur le CDN de Pic-Time) et ses métadonnées :

- la liste des photos et leurs **scènes** (préparatifs, cérémonie…), dans l'ordre de la galerie ;
- l'**orientation** de chaque photo, sans la télécharger ;
- les photos **mises en avant** par la photographe (affichées en grand, ou dans la scène « Highlights ») : un signal fort pour la sélection ;
- l'**heure de prise de vue**, utile pour construire une progression ;
- le **nom de fichier d'origine**, qui permet de retrouver l'export pleine définition sur l'ordinateur ;
- une palette de couleurs, qui aide à reconnaître le noir et blanc.

Les images se téléchargent en trois tailles : vignette, 640 px (pour l'analyse) et **1 600 px** (pour la publication). Pour un recadrage serré d'une image horizontale, 1 600 px peut être juste : indique alors dans la série un dossier `exports_hd` (tes exports pleine définition). Le studio y retrouve chaque photo par son nom de fichier d'origine.

## Si une galerie ne s'ouvre pas

- **« Pic-Time ne donne pas accès… »** : le lien demande un code ou une inscription. Reprends le lien de partage direct (avec `sectoken2`).
- **Pic-Time a changé son format** (le studio lit un format interne, qui peut évoluer) : la commande échoue proprement, sans rien casser. En attendant une mise à jour du script, utilise une source **dossier** :

```yaml
source:
  type: dossier
  chemin: "~/Pictures/Exports/mas-exemple-2026"
```

Le studio lit alors les JPEG du dossier (et leur heure de prise de vue). Un dossier Google Drive synchronisé sur le Mac fonctionne de la même façon.

## Respect des clients

Le studio ne télécharge que les galeries que tu lui donnes, ne publie rien sans ta validation, n'écrit les prénoms des mariés que si la série l'autorise, et ne garde les photos qu'en local, dans `catalogue/`. Pour retirer une série : supprime-la de `config/galeries.yaml` et efface `catalogue/<série>/`.
