---
name: studio-bilan
description: Bilan hebdomadaire du Studio Instagram. Analyse les performances et les choix de la semaine, réécrit les apprentissages, propose une ou deux expériences et des ajustements. À lancer chaque dimanche (tâche planifiée) ou quand la photographe demande « le bilan ».
---

# Bilan de la semaine

## 0. Se placer dans le studio

Le dossier du studio est le dossier courant s'il contient `config/compte.yaml` ; sinon le chemin donné par la tâche planifiée ; sinon `~/Studio-Instagram`. Place-toi dedans (`cd`). S'il n'existe pas encore, lance le skill `studio-instagram:studio-installation`.
Mets ensuite le moteur à jour si le plugin a changé (instantané s'il est déjà à jour) : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" --si-besoin "$PWD"`.

1. `./studio releve`, puis `./studio analyse`. Lis `memoire/performance.md`.
2. Lis les 7 derniers jours de `donnees/choix.jsonl` (idées proposées et choisies), `donnees/retouches.jsonl` (demandes de retouche) et `donnees/validations.jsonl` (légendes finales). Compare ce que tu avais écrit et ce qui a été publié : c'est la meilleure source pour comprendre son style.
3. Réécris `memoire/apprentissages.md` (60 lignes au plus), en quatre parties :
   - **Ce qui fonctionne** (avec le niveau de confiance : simple indice, à confirmer, solide) ;
   - **À améliorer** ;
   - **Préférences de la photographe** (choix, refus, retouches récurrentes) ;
   - **À tester la semaine prochaine** : deux ou trois expériences précises et compatibles avec la charte (un pilier, un format, une longueur de légende, un créneau).
   Remplace ce qui est dépassé, garde les leçons solides.
4. Si `memoire/gouts.md` dépasse 80 lignes, condense-le (fusionne les doublons, garde les dates des observations récentes).
5. Message pour elle, cinq lignes au plus et sans jargon : la publication qui a le mieux marché et pourquoi, une chose à améliorer, l'expérience proposée. Si un réglage aiderait (heure d'un créneau, part de Reels, nombre d'idées), demande-lui avec AskUserQuestion ; ne modifie `config/compte.yaml` qu'après son accord.
6. PushNotification « Ton bilan de la semaine est prêt » si elle n'est probablement pas devant l'écran.
