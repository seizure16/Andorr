# Andorr — contexte durable

Application macOS gratuite et open source (MIT) pour les notes de cours Markdown et le suivi des révisions. Interface française, propre et discrète ; priorité à la fluidité de l’éditeur. Ce fichier contient les invariants et conventions. Consulter `PROJECT_STATUS.md` seulement pour reprendre un chantier ; `README.md` pour les comportements détaillés.

## Architecture

- Swift + SwiftUI, macOS 14 minimum. Swift tools 6.2, mode de langage Swift 5. Deux zones avec `NavigationSplitView`.
- `Sources/AndorrCore/` : modèles `Note`, arborescence `NoteTree`, `FrontmatterCodec`, acteur `MarkdownRepository`, rendu HTML `MarkdownRenderer`, analyse des styles `MarkdownEditorSyntax`. Dépendances SPM épinglées : Yams 6.2.2 et swift-markdown 0.8.0.
- `Sources/Andorr/` (cible SPM `AndorrDesktop`, cible Xcode `Andorr`) : `WorkspaceStore` observable sur le MainActor, vues SwiftUI, `FolderAccessManager`, préférences et cycle de vie.
- `MarkdownEditor.swift` : pont `NSViewRepresentable` vers `NSTextView` et layout AppKit personnalisé ; édition brute et aperçu en direct partagent le même éditeur. `MarkdownDelimiterCompletion.swift` gère les paires automatiques et leur historique. `MarkdownCodeHighlighter.swift` isole Highlightr 2.3.0 sur un acteur et applique uniquement les couleurs aux blocs avec langage explicite.
- `MarkdownPreview.swift` : aperçu de lecture HTML dans `WKWebView`, JavaScript désactivé, sans chargement d’images ; liens externes ouverts uniquement sur action utilisateur.
- `Tests/AndorrCoreTests/` et `Tests/AndorrDesktopTests/` : tests Swift Package, distincts de la cible application Xcode.

## Données et sauvegarde : invariants

- Les `.md` locaux sont la source de vérité. Dossiers imbriqués = matières, fichiers racine acceptés. Identité d’une note = chemin relatif. Index et filtres en mémoire, aucune base de données dans les cours.
- YAML initial : `status` (`in_progress`, `to_review`, `reviewed`) et `tags`. Sans YAML : En cours, aucun tag ; ouvrir ou modifier seulement le corps ne crée pas d’en-tête. Préserver l’en-tête original lors d’une modification du corps et les clés inconnues lors d’un changement de métadonnées. Métadonnées invalides : lecture seule.
- Texte sauvegardé après 500 ms d’inactivité ; statut/tags immédiatement. Un worker sérialise les instantanés : une ancienne sauvegarde ne doit jamais restaurer un ancien statut. Vider les modifications avant navigation, fermeture ou sortie ; conserver le brouillon en cas d’échec.
- Le repository utilise `NSFileCoordinator`, compare les octets attendus avant écriture et écrit atomiquement les fichiers existants. Ne jamais contourner la coordination en production ni écraser silencieusement un conflit.
- App Sandbox activé ; dossier choisi via panneau natif, accès conservé par security-scoped bookmark. Refuser les chemins hors racine ; ignorer liens symboliques, fichiers cachés et packages. Préférences et bookmark dans `UserDefaults`.

## Éditeur et interface : règles à préserver

- Le Markdown source reste intact : masquer les glyphes des balises, pas supprimer les caractères. Plages AppKit en UTF-16 ; convertir correctement les positions UTF-8 du parseur.
- Analyse en arrière-plan avec rejet des résultats périmés et remise en forme limitée aux plages touchées. Préserver sélection, scroll, composition IME et undo natif propre à la note. Les transitions de taille des titres sont synchrones pour éviter un saut visuel.
- Balises inline visibles pendant l’édition de leur élément, masquées après sa fermeture ; `#` visible sur toute la ligne active. La tolérance aux espaces avant une fermeture reste réservée à l’édition, sans changer le rendu CommonMark strict.
- Pas d’indicateur de sauvegarde animé pendant la frappe ; erreurs visibles. Sélections discrètes, badges lisibles, icônes de dossiers non pleines, clic sur toute la ligne et repli animé.
- Préférences centralisées dans `PreferenceKeys`. Couleurs via `Palette` et thème résolu explicitement pour SwiftUI et WebKit ; vérifier sombre → clair et sombre → système clair.

## Travail et validation

- Sources partagées entre SPM et Xcode : tout nouveau fichier doit aussi être référencé dans `Andorr.xcodeproj/project.pbxproj` (listes explicites).
- Commandes usuelles : `swift test`, `bash Scripts/build-app.sh` (bundle ad hoc `build/Andorr.app`), `bash Scripts/check.sh` (tests puis Xcode). Utiliser le Xcode complet via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` si nécessaire.
- Vérifier les régressions utiles au changement ; pour l’éditeur, inclure les interactions natives et pas seulement l’analyse syntaxique. Ne pas présenter des tests unitaires comme une validation visuelle de l’app sandboxée.
- Icône source : document `icon.icon`, ressource Xcode, App Icon = `icon`. Le script compile avec `actool`, intègre les ressources et métadonnées avant signature.
- Répondre en français ; identifiants et messages Conventional Commits en anglais. Une demande de message de commit n’autorise pas à exécuter `git commit`.
- Pas de synchronisation, comptes, plugins ou portage Windows/Linux dans le périmètre actuel. Éviter les refontes ou dépendances sans besoin concret.

Maintenir ce fichier court : décisions durables seulement ; déplacer avancement, erreurs d’environnement et prochaines étapes dans `PROJECT_STATUS.md`.
