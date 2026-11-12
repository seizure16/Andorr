# Andorr

Application macOS gratuite et open source pour écrire ses cours en Markdown et suivre ses révisions. Les dossiers représentent les matières ; les notes restent des fichiers locaux lisibles dans n’importe quel éditeur.

## Ouvrir le projet

- macOS 14 ou ultérieur pour utiliser l’application.
- Xcode 26 ou ultérieur avec Swift 6.2 ou ultérieur pour compiler.
- Un accès à GitHub est nécessaire pour la première résolution des dépendances.

Ouvrir **`Andorr.xcodeproj`**, laisser Xcode résoudre les packages, sélectionner le schéma **Andorr**, puis lancer avec **⌘R**. La signature est configurée en local (ad hoc) : aucun compte développeur payant n’est nécessaire pour les essais sur ce Mac. La distribution signée et notariée sera traitée séparément.

Une application compilée pour le Mac de développement est également disponible dans **`build/Andorr.app`**. Pour la reconstruire sans passer par l’interface Xcode :

```sh
bash Scripts/build-app.sh
```

Ce script compile les mêmes sources via Swift Package Manager, assemble le bundle macOS et le signe localement avec les mêmes autorisations sandbox. Il ne publie et n’installe rien.

Le projet active l’App Sandbox et l’accès en lecture/écriture aux dossiers sélectionnés. L’application conserve un security-scoped bookmark pour rouvrir le dernier dossier au lancement suivant si cette option est activée (par défaut). Si cet accès expire ou si le dossier n’existe plus, le sélectionner à nouveau.

L’explorateur affiche une arborescence de dossiers imbriqués, avec indentation, dossiers avant les notes et notes racine en bas de la liste. Les lignes de dossiers sont cliquables et le bouton global permet de tout replier ou déplier avec animation. Après remplacement de l’application, la quitter puis la relancer pour appliquer les nouvelles autorisations WebKit.

## Icône de l’application

Le document Icon Composer **`icon.icon`** est la source de l’icône. Il est référencé dans les ressources de la cible Andorr ; le réglage **App Icon** (`ASSETCATALOG_COMPILER_APPICON_NAME`) vaut **`icon`**, le nom du document sans extension. Modifier ce document dans Icon Composer, l’enregistrer puis reconstruire l’application pour appliquer une nouvelle version.

Le script `Scripts/build-app.sh` compile aussi ce document avec l’outil Apple `actool`, copie les ressources produites dans le bundle et fusionne leurs métadonnées avant la signature. Une erreur de compilation de l’icône arrête la construction avant de remplacer l’application existante. Les outils fournis avec Xcode doivent pouvoir ouvrir et exporter le document `.icon`.

## Premier essai

Utiliser une **copie** de `Examples/Cours S3` si vous souhaitez conserver les exemples intacts : l’application modifie les fichiers choisis.

1. Ouvrir le dossier `Cours S3` dans l’application (**⌘O**).
2. Sélectionner **Graphes et parcours**, une note sans en-tête YAML.
3. Passer son statut à **À revoir**. La sauvegarde est automatique ; **⌘S** permet aussi de la déclencher immédiatement.
4. Activer **À revoir** dans la barre latérale : la note reste visible dans sa matière.
5. Quitter avec **⌘Q**, puis relancer. Le dossier est restauré ; activer le filtre et sélectionner la note pour vérifier son statut.
6. Vérifier dans le fichier `.md` que `status: to_review` a été ajouté et que le corps du cours a été conservé.

Essayer ensuite l’édition, l’aperçu, les tags, la recherche sans accents et les deux options du menu **Affichage**. Les filtres de recherche, statut et tag se combinent ; les filtres ne sont pas restaurés entre deux lancements. Une note ouverte reste affichée quand elle cesse de correspondre au filtre.

## Fonctions du premier jet

- Explorateur hiérarchique : dossiers imbriqués, dossiers vides, notes `.md` et tri naturel à chaque niveau.
- Notes à la racine affichées directement après les dossiers, sans groupe artificiel ni déplacement sur disque.
- Création d’une note dans une matière existante ou à la racine (**⌘N**).
- Édition Markdown brut avec NSTextView, premier aperçu en direct et aperçu de lecture ; sauvegarde après 500 ms d’inactivité.
- Statuts et tags enregistrés immédiatement ; affichage indépendant dans la barre latérale.
- Recherche dans le titre (nom de fichier) et le corps, insensible à la casse et aux accents.
- Filtres transversaux par statut (**En cours**, **À revoir**, **Révisé**) pour les statuts affectés aux notes, filtre par tag et compteurs globaux. Les filtres conservent les dossiers parents des résultats et les ouvrent automatiquement ; leur fermeture temporaire ne modifie pas les dossiers ouverts ou repliés avant le filtre.
- Annuler avec **⌘Z** et rétablir avec **⇧⌘Z** dans l’éditeur ; historique propre à la note courante, transmis à la sauvegarde automatique.
- Sauvegarde normale silencieuse, sans texte changeant ni animation pendant la frappe ; les erreurs restent visibles.
- Vidage des modifications en attente avant navigation, fermeture et sortie.
- Vérification des changements externes avant écriture ; brouillon conservé en cas de conflit.
- Actualisation au retour dans l’application et avec **⇧⌘R**.
- États vides et erreurs de lecture/sauvegarde visibles.

## Aperçu en direct

Le sélecteur en haut de la note propose trois icônes : édition brute, aperçu en direct et aperçu de lecture. Le mode est également accessible dans **Affichage → Mode de la note** et peut être choisi comme mode d’ouverture dans les réglages.

Cette première version applique une mise en forme aux titres, au gras, à l’italique, aux citations, aux liens et au code pendant la saisie. Les marqueurs des titres, du gras, de l’italique, du code en ligne et des liens sont masqués sans occuper d’espace. Les balises de gras, d’italique, de code en ligne et de liens restent visibles pendant l’édition de leur élément. Elles se masquent dès que le curseur franchit la fermeture, même si la phrase continue sur la même ligne, et réapparaissent quand on revient dans l’élément. Le `#` des titres reste visible sur toute la ligne du titre, espaces de fin compris. Les changements de niveau des titres ATX appliquent leur taille pendant la saisie native, pour éviter une seconde mise à l’échelle lors du résultat de l’analyse en arrière-plan. Pendant l’édition de la ligne, une tolérance conserve le gras et l’italique lorsque des espaces sont insérés juste avant les délimiteurs de fermeture. Cette tolérance ne modifie pas le fichier ni le parseur strict de l’aperçu de lecture. Le copier-coller conserve le Markdown source. Le Markdown sauvegardé est inchangé. L’analyse utilise le même parseur CommonMark que l’aperçu et se déroule en arrière-plan pendant la frappe, avec un seul traitement actif qui reprend le texte le plus récent. Seuls les paragraphes modifiés et les éléments dont la syntaxe a changé sont remis en forme ; les déplacements du curseur ne recalculent pas les polices du document. Le rendu est figé pendant une sélection à la souris et les compositions de saisie sont préservées.

Les blocs de code avec un langage explicite (`bash`, `python`, `swift`, `js`, etc.) sont colorés en aperçu direct, avec une palette adaptée au thème clair ou sombre. Seules les couleurs du contenu sont appliquées : le Markdown, les polices et la mise en page restent inchangés. Sans langage ou avec un langage inconnu, le rendu reste neutre. La coloration se déroule en arrière-plan et réutilise les blocs inchangés ; les blocs de plus de 50 000 unités UTF-16 restent neutres pour limiter le travail pendant la saisie.


Le code en ligne reçoit un fond discret arrondi ; les blocs de code utilisent une police monospace, un retrait et un fond sur toute la largeur. Les lignes de délimiteurs (avec langage éventuel) se révèlent lorsque le curseur les atteint et restent masquées dans le corps du bloc. Les listes et les citations gardent leurs marqueurs ; les images ou tableaux ne sont pas rendus dans l’éditeur. L’aperçu de lecture conserve le rendu complet déjà disponible. Le passage entre les trois modes conserve l’éditeur et sa sélection ; changer de note remet l’historique d’annulation à zéro.

La fermeture automatique du gras et de l’italique est activée par défaut, en édition brute comme en aperçu en direct. Taper `*` prépare une paire d’italique ; le second `*` transforme la paire vide en gras. Le même comportement fonctionne avec `_` et `__`. Le curseur reste entre les balises ; retaper une fermeture ajoutée automatiquement la franchit sans la doubler. Une sélection peut être entourée, Retour arrière supprime une paire vide et les opérations participent à l’historique natif d’annulation. La complétion ne s’applique pas dans le code, aux balises échappées ou au contenu collé. Elle peut être désactivée dans **Réglages → Éditeur**.

## Réglages

Ouvrir **Andorr → Réglages…**, utiliser **⌘,** ou cliquer sur l’engrenage en bas de la barre latérale. Les trois groupes sont empilés dans une fenêtre native :

- **Apparence** : thème système, clair ou sombre ; affichage des statuts et des tags.
- **Éditeur** : fermeture automatique des balises de gras et d’italique ; taille du texte de 70 à 200 %, aperçu de la taille et réinitialisation ; mode d’ouverture des notes existantes.
- **Dossier de cours** : réouverture du dernier dossier au lancement ; nom, chemin et changement du dossier actuel.

Les préférences sont mémorisées automatiquement. La visibilité des métadonnées reste synchronisée avec le menu Affichage ; la taille du texte reste synchronisée avec **⌘+**, **⌘−** et **⌘0** et s’applique à l’éditeur et à l’aperçu. Le thème s’applique aux deux fenêtres et au rendu Markdown. Le mode choisi s’applique à la prochaine note ouverte ; les nouvelles notes s’ouvrent en édition et une actualisation conserve le mode choisi pour la note courante. Désactiver la réouverture prend effet au prochain lancement. Changer de dossier passe par la sauvegarde habituelle du brouillon.

## Format des fichiers

```markdown
---
status: to_review
tags:
  - cours
  - examen
---
# Mon cours

Le contenu de la note.
```

Les valeurs de statut sont `in_progress`, `to_review` et `reviewed`. Les libellés français existants sont également reconnus à la lecture. Une note sans métadonnées utilise implicitement **En cours** et aucun tag ; l’ouvrir ne la réécrit pas. Une modification du texte seule ne crée pas d’en-tête.

Un en-tête commence par `---` sur la première ligne (BOM UTF-8 accepté) et se termine par `---` ou `...`. Les propriétés YAML inconnues sont conservées lors des modifications de statut ou de tags. Ces modifications peuvent normaliser la présentation et supprimer les commentaires du YAML. Une modification du corps seule conserve l’en-tête original. Les fichiers sont lus en UTF-8 ; les fins de ligne du corps sont conservées.

Un en-tête invalide ou un statut non reconnu affiche la note en lecture seule avec une explication. Un fichier qui ne peut pas être lu est signalé dans le pied de la barre latérale. Les fichiers cachés, les packages et les liens symboliques sont ignorés pendant l’indexation. Les écritures hors du dossier autorisé sont refusées.

## Sauvegarde et conflits

Les écritures sont sérialisées dans un acteur, coordonnées avec `NSFileCoordinator`, et atomiques pour les fichiers existants. Le contenu disque est comparé à la dernière version chargée avant chaque sauvegarde. En cas d’erreur, la note courante reste ouverte et le brouillon reste en mémoire. Trois actions sont proposées : réessayer, enregistrer une copie, ou recharger le fichier après confirmation de l’abandon du brouillon.

Cette protection réduit le risque d’écrasement par un autre éditeur ; elle ne constitue pas un verrou universel contre les processus qui ne coopèrent pas avec la coordination macOS. Les brouillons non enregistrés ne sont pas récupérables après un arrêt forcé ou un crash.

## Architecture

```text
Sources/Andorr/             Interface SwiftUI, état observable, cycle de vie, accès au dossier
Sources/AndorrCore/         Modèles, recherche, codec YAML, stockage sur acteur, rendu Markdown
Tests/AndorrCoreTests/      Persistance, format, conflits, isolation des chemins et recherche
Tests/AndorrDesktopTests/   Sélection des notes, ordre des matières et navigation de l’aperçu
Resources/                 Autorisations sandbox
Examples/Cours S3/          Sept notes de démonstration
```

`WorkspaceStore` est isolé sur le MainActor. `MarkdownRepository` gère le disque sur son propre acteur. Un seul worker de sauvegarde traite les instantanés successifs du brouillon : une ancienne sauvegarde de texte ne doit pas restaurer un ancien statut. L’index vit en mémoire et se reconstruit depuis les fichiers ; aucune base de données ni aucun fichier d’index n’est écrit dans le dossier de cours.

Les préférences d’affichage et le bookmark restent dans les préférences de l’application. L’identité d’une note est son chemin relatif ; le suivi d’un renommage externe n’est pas encore implémenté.

Dépendances via Swift Package Manager : [Yams](https://github.com/jpsim/Yams) pour le YAML et [Swift Markdown](https://github.com/swiftlang/swift-markdown) pour l’analyse CommonMark/GFM, et [Highlightr](https://github.com/raspu/Highlightr) 2.3.0 pour la coloration des blocs de code dans l’aperçu en direct. L’aperçu génère du HTML depuis l’arbre Markdown, dans un `WKWebView` sans JavaScript ni chargement d’images. L’autorisation sandbox `network.client` permet l’initialisation des processus WebKit, y compris pour du HTML local ([suivi WebKit](https://bugs.webkit.org/show_bug.cgi?id=219632)). La politique de navigation accepte le chargement HTML synthétique et les ancres locales ; elle refuse les navigations distantes automatiques. Les liens HTTP(S) et mailto activés par l’utilisateur s’ouvrent dans l’application externe correspondante. Un échec de chargement ou un arrêt du moteur affiche un message et permet de réessayer.

## Vérifications

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Andorr.xcodeproj -scheme Andorr \
  -configuration Debug -derivedDataPath build/DerivedData build
```

Ou exécuter `bash Scripts/check.sh`. Les tests sont deux cibles Swift Package, distinctes de la cible application Xcode.

Les tests couvrent notamment le jalon statut → sauvegarde → nouvelle instance du stockage → filtre, les notes sans YAML, la conservation du corps et des propriétés inconnues, les fins de ligne, les métadonnées invalides, les conflits externes, les doublons et les liens symboliques. Le bookmark, la fermeture de fenêtre et le confort visuel nécessitent également un essai dans l’application native sandboxée.

État de validation dans l’environnement de création : les vrais packages ont été résolus et verrouillés dans `Package.resolved`. L’application a été compilée via Swift Package Manager et le bundle signé localement. Les **79 tests passent** (34 pour le cœur et 45 pour l’éditeur natif, la sélection des notes, les filtres, les préférences, les couleurs clair/sombre et la navigation de l’aperçu) avec `ANDORR_TEST_COORDINATION=direct` : cet adaptateur réservé aux tests remplace le service système de coordination indisponible dans le lanceur, mais conserve les vrais fichiers, le parseur YAML, le rendu Markdown, les comparaisons de versions et les écritures de production. Sans cette variable, les tests emploient la coordination native comme l’application. Aucun repli non coordonné n’est activé dans l’application.

`xcodebuild` s’arrête dans cet environnement avec le code 134 avant la compilation ; le projet et les autorisations ont été vérifiés avec `plutil`. Le service de contrôle de l’interface ne démarre pas non plus. L’essai visuel, le bookmark et le parcours de relance dans l’application sandboxée restent à vérifier sur le bureau macOS.

## Limites assumées

Pas de synchronisation, de comptes, de plugins, de renommage/déplacement ou suppression de notes depuis l’application. Les matières se créent pour l’instant dans Finder. Pas de coloration syntaxique dans l’éditeur, de rendu mathématique, d’images dans l’aperçu ou d’animations personnalisées. Les changements externes sont relus à l’activation ou sur actualisation ; il n’y a pas encore de surveillance continue du dossier.

## Licence

[MIT](LICENSE). Les dépendances conservent leurs licences respectives. La maquette HTML fournie sert de référence visuelle ; son code et ses polices embarquées ne sont pas intégrés à l’application.
