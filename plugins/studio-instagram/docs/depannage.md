# Dépannage

| Ce qui s'affiche | Ce que ça veut dire | Que faire |
|---|---|---|
| « Le studio n'est pas installé dans ce dossier » | le dossier de travail n'a pas été préparé | dans Claude : `/studio-instagram:studio-installation` |
| « Python 3 est introuvable » | outils développeur Apple absents | dans le Terminal : `xcode-select --install`, puis relancer l'installation |
| « Jeton Instagram absent » | Instagram pas encore connecté | `docs/connexion-instagram.md` |
| « Jeton Instagram invalide » ou « a expiré » | le jeton de 60 jours est périmé, ou le mot de passe Facebook a changé | refaire « Obtenir le jeton » (route A) puis « c'est fait » |
| « Pic-Time ne donne pas accès à cette galerie » | le lien demande un code ou une inscription | copier le lien de partage direct (`docs/pic-time.md`) |
| « cloudflared est absent » | l'outil d'adresse temporaire n'a pas été téléchargé | relancer l'installation (`/studio-instagram:studio-installation`), ou passer à Supabase |
| « L'adresse temporaire ne répond pas » | réseau qui bloque Cloudflare | réessayer plus tard, ou passer à Supabase (`docs/connexion-instagram.md`) |
| « Instagram a refusé : … aspect ratio » | une image hors format | relancer `./studio rendre <jour>` (toutes les images sont remises en 4:5) |
| « Identification refusée … publiée sans » | un compte identifié n'existe pas ou n'accepte pas les identifications | corriger le compte dans `config/galeries.yaml` |
| « Collaborateurs ou lieu refusés » | un collaborateur ou un identifiant de lieu non valide | le post est parti sans ; corriger la série |
| La tâche du matin n'a pas tourné | l'application Claude était fermée ou le Mac en veille | elle part au prochain lancement ; garder l'app ouverte |
| Une tâche reste bloquée sur une autorisation | la tâche n'a pas été créée en mode Auto | ouvrir la tâche, autoriser, puis la recréer en mode Auto (`/studio-instagram:studio-installation`, étape 6) |
| Pas de notification sur le téléphone | Contrôle à distance non activé | réglages de l'application Claude |
| Les commandes `/studio-instagram:…` n'apparaissent pas | le plugin n'est pas installé ou pas activé | voir le README du catalogue (installation du plugin), puis redémarrer l'application |

Pour un diagnostic complet : `./studio verifier`.

Pour une publication sans risque (rien n'est envoyé, on voit seulement les requêtes) : `./studio publier <jour> --simulation`.
