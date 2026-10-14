# RemindersInt

## Vision
App iOS native de rappels à saisie vocale ultra-rapide. Le problème : les micro-tâches orales ("rappelle-moi d'appeler Karim") se perdent parce que les saisir dans Rappels ou Calendrier coûte trop cher sur le moment.
Promesse : capturer un rappel en moins de 3 secondes depuis l'écran verrouillé, et être relancé jusqu'à ce que ce soit fait.

## Utilisateur V1
Un seul utilisateur : le développeur, sur son iPhone 17 Pro Max, installé via Xcode avec un Apple ID gratuit. Pas d'App Store, pas de backend, pas de compte.

## Métrique de succès V1
Après une semaine d'usage réel : l'app est toujours utilisée chaque jour, et le nombre de rappels oubliés a baissé.

## Hors périmètre (interdit sans demande explicite)
Comptes, synchronisation, cloud, partage, Android, pièces jointes, Siri, Apple Watch, widgets écran d'accueil autres que celui décrit, dark mode custom, onboarding, analytics, dépendances externes.

## Stack imposée
- iOS 26+, SwiftUI, Swift 6, Xcode 26
- Persistance : SwiftData (modèle local uniquement)
- Notifications : UserNotifications (locales, avec UNNotificationCategory et actions)
- Voix : Speech framework (SFSpeechRecognizer, fr-FR, on-device si dispo)
- Extraction : Foundation Models framework (LanguageModelSession + @Generable), on-device, pas d'API cloud
- Widget : WidgetKit + AppIntents (iOS 17+), pour le bouton écran verrouillé
- Aucune dépendance Swift Package externe

## Architecture
- Dossiers : Models / Views / ViewModels / Services / Widget
- Modèles SwiftData (V2, étape 6a) :
  - TaskItem (la « Task » du plan ; nommée ainsi car `Task` masquerait Swift Concurrency)
    - id: UUID, title: String, dueDate: Date?, repeatInterval: enum RepeatInterval { none, every5min, every15min, every30min, hourly }
    - status: enum ReminderStatus { pending, done, cancelled }, createdAt: Date, remindersSent: Int
    - rawTranscript: String? (ce qui a été dicté, pour debug), note: String?
    - isReminder: Bool (true = rappel avec relances comme en V1 ; false = tâche, une seule notification à l'échéance si elle existe)
    - space: Space?
  - Space : id, name, colorHex, sfSymbol, sortOrder, isArchived, createdAt, parent: Space?, children (cascade), tasks (nullify). Arbre à profondeur illimitée, un seul parent.
  - Reminder : modèle V1 conservé uniquement comme stockage hérité, vidé au lancement par `StoreSetup` (voir Décisions).
- Services :
  - NotificationService : planifie, annule et replanifie les notifications locales des TaskItem en attente et datés ; relances selon repeatInterval pour les rappels, notification unique pour les tâches
  - SpeechService : transcription voix -> texte
  - ParserService : texte -> ParsedCapture via Foundation Models : intention (reminder / task ; session et goal prévus, non produits), titre, date/heure absolue, intervalle de relance, jusqu'à 3 espaces probables avec confiance. Date de référence = maintenant, en Europe/Paris, français. Un rappel sans date fait demander la date plutôt que d'inventer ; une tâche peut rester sans date.
  - SpaceRouter : routage de secours par mots-clés sur les noms d'espaces et leurs synonymes. Seuil de confiance 0,6.

## Écrans (design validé, style Liquid Glass iOS 26)
1. Widget écran verrouillé : petit carré en verre avec icône micro, en bas à gauche. Un tap lance la capture vocale.
2. Capture vocale : panneau en verre par-dessus l'écran verrouillé. Indicateur "En écoute", transcription en direct, barre d'onde façon Dictée iOS, bouton vert en verre à droite pour valider. Après validation : le rappel est créé sans ouvrir l'app.
3. Notification : titre "Rappel", corps = titre du rappel, sous-ligne "Ne relance · prochaine dans X min". Deux actions directement sur la notif : Annuler (rouge) et Fait (vert).
4. Vue Jour (écran principal) : fond gris clair iOS avec légère teinte, cartes en verre blanc. En haut "MARDI 29 SEPT." puis "Aujourd'hui" en gros, boutons calendrier et engrenage (Réglages) à droite. Sélecteur de 5 jours (jour courant en noir). Liste des rappels et tâches datés : heure en gras, trait de la couleur de l'espace (neutre sans espace), titre, sous-ligne espace · relance, icône de statut (refresh si rappel en attente, cercle si tâche à faire, check vert si done, barré et grisé si annulé). Barre d'onglets flottante en verre (Jour / Calendrier / Espaces / Suivi) avec gros bouton micro vert à droite.
5. Vue Mois : grille du mois dans une carte en verre, point vert sous les jours qui ont des rappels, jour sélectionné en noir, liste des rappels du jour sélectionné dessous (même carte que la Vue Jour, couleur d'espace), lien "Voir la journée".
9. Hub Espaces : fond et cartes en verre comme la Vue Jour. En-tête "SEMAINE 42" en petit gris, puis "Espaces" en 34 pt bold, bouton + en verre à droite. Carte de résumé en verre sur deux colonnes séparées par un trait : "À faire cette semaine" 11 dont 3 en retard, "Temps tracké" 31h avec delta vert "+4h". Puis une carte en verre par espace racine : pastille carrée 40 pt coins 13 pt de la couleur de l'espace avec son SF Symbol en blanc, nom en 16 pt bold, sous-titre 12 pt gris (ex. "4 cours · 5 tâches · 18h cette semaine"), badge rouge "2 en retard" en pastille rouge translucide si besoin, chevron à droite sinon. Sous le nom, quand un objectif existe : libellé court en 12 pt gris sur 118 pt + barre de progression 6 pt de la couleur de l'espace + pourcentage ou "3/10" en bold. Couleurs des espaces de démo : Études #5E5CE6, FieldZ #FF9F0A, Sport #34C759, Mawiid #0A84FF, Perso #FF375F. Barre d'onglets : Jour / Calendrier / Espaces (actif, rond noir) / Suivi + micro vert.
10. Espace ouvert (Études) : en-tête avec bouton retour en verre, pastille couleur + nom 24 pt bold + sous-titre "18h cette semaine · 5 tâches". Rangée de puces horizontales : "Tout" en noir plein, puis un sous-espace par puce en verre (Finance, Maths, TAGE MAGE, Anglais) ; un tap sur une puce navigue vers cet enfant. Section "Objectifs" avec lien "Ajouter" bleu : carte en verre, une ligne par objectif = libellé 14 pt semibold à gauche, valeur à droite en bold, barre 6 pt dessous ; pour un objectif à échéance sans progression, la date en gris à droite. Section "Tâches" avec "par échéance" en gris : une carte en verre par tâche, cercle 22 pt à gauche (bord rouge si en retard, gris sinon, rempli vert avec check si faite), titre 14 pt semibold, sous-ligne 12 pt "Sous-espace · échéance" (rouge si en retard, "sans date" si vide), tâches faites barrées à 60 % d'opacité. En bas, au-dessus de la barre d'onglets, le toast de routage vocal : capsule noire, check vert, "Tâche ajoutée dans Études › Finance" en 13 pt bold, la phrase dictée en dessous à 70 %, bouton "Changer" à droite.

Palette : fond #F2F2F7, texte #1C1C1E, secondaire #6E6E73, vert #34C759, rouge #FF453A, cartes blanches translucides avec .glassEffect() quand dispo, sinon .ultraThinMaterial. Police système (SF). Coins 20 à 28 pt. Pas d'emoji.

## Règles de travail
- Avancer par étapes, une fonctionnalité à la fois, un commit par étape.
- Le projet doit compiler sans warning et tourner sur simulateur ET sur iPhone physique à la fin de chaque étape.
- Ne jamais ajouter de fonctionnalité hors périmètre sans demande explicite.
- Si une API iOS 26 n'est pas disponible ou incertaine (Foundation Models, glassEffect), le dire clairement et proposer le fallback le plus simple plutôt que de contourner en silence.
- Code et commentaires en anglais, textes UI en français.

## Plan
- [x] Étape 1 : modèle SwiftData + Vue Jour + Vue Mois + ajout/édition manuelle + Fait/Annulé. Pas de notif, pas de voix, pas de widget.
- [x] Étape 2 : NotificationService + relances + actions Fait/Annulé sur la notification.
- [x] Étape 3 : SpeechService + ParserService (Foundation Models) + écran de capture vocale dans l'app.
- [x] Étape 4 : widget écran verrouillé + App Intent qui ouvre la capture vocale.
- [x] Étape 5 : polish Liquid Glass. V1 livrée, tag `v0.1.0`.

## V2 : Espaces, suivi du temps, objectifs
La semaine d'usage réel de la V1 se fait en parallèle de la V2.
- [x] Étape 6a : Espaces (arbre), TaskItem (généralise Reminder), hub et détail d'espace, routage vocal intention + espace, toast « Changer ».
- [ ] Étape 6b : Suivi du temps (sessions par espace, onglet Suivi, « Temps tracké » du hub, intention `session`).
- [ ] Étape 6c : Objectifs par espace (bloc Objectifs, barres de progression du hub, intention `goal`).

## Décisions prises en cours de route
- Étape 2 : compteur remindersSent = notifications délivrées, première incluse (libellé « Notifications envoyées »). Rattrapage app fermée par calcul des heures passées. Suppression : swipe complet à gauche (avec confirmation) et bouton dans le détail.
- Étape 3 : `Date` n'est pas `@Generable`, le modèle renvoie une date ISO `AAAA-MM-JJTHH:MM` convertie ensuite. Parser de secours en Swift pur si Foundation Models est indisponible ou échoue (note dans Réglages). Champ « Simuler une dictée » en DEBUG uniquement.
- Étape 4 : option A retenue, un ControlWidget (`ControlWidgetButton` + `StartVoiceCaptureIntent`, `openAppWhenRun`) placé en bas de l'écran verrouillé ou dans le Centre de contrôle. Vérifié sur simulateur via le Centre de contrôle : un tap lance l'app fermée directement sur la dictée. iOS impose le premier plan pour le micro : depuis l'écran verrouillé, le tap déclenche Face ID puis l'app s'ouvre déjà en écoute ; il n'existe pas de dictée sans déverrouiller.
- Étape 4 : deep links `remindersint://capture` et `remindersint://reminder/<uuid>`. Widget `accessoryRectangular` « Prochain rappel » alimenté par un instantané JSON écrit par l'app dans l'App Group `group.com.yacine.RemindersInt` (le widget ne lit pas SwiftData). Code commun app/extension dans `Shared/`.
- Étape 5 (polish) : cible iOS 26.5, donc `.glassEffect` partout, aucun fallback Material. La dictée n'est plus une feuille mais un panneau superposé dans `ContentView` (app floutée et assombrie dessous, ressort depuis le bas, fermeture par tap sur le fond ou glissement vers le bas). Onglets en icônes seules, libellés en accessibilité. Ressort commun `Animation.appSpring` ; l'ouverture des feuilles système garde l'animation iOS (non personnalisable). Arguments DEBUG pour les captures : `-uiTab day|month|settings`, `-uiScreen capture|detail|form`.

- Étape 6a : SwiftData ne sait pas renommer une entité. `Reminder` reste dans le schéma (ajout de `TaskItem` et `Space` = migration légère additive) et `StoreSetup.run`, appelé dans `App.init` avant toute réponse de notification, copie chaque Reminder en TaskItem `isReminder = true`, `space = nil`, même `id` (les notifications planifiées et les deep links restent valides), puis le supprime. Vérifié sur simulateur avec un store V1.
- Étape 6a : espaces de démo semés une fois (`hasSeededSpaces`), aussi sur un store existant. Webentis en #30B0C7, sous-espaces à la couleur du parent. 8 couleurs et 12 symboles dans `SpaceStyle`.
- Étape 6a : un seul appel Foundation Models par dictée (intention + extraction + 3 espaces candidats) pour tenir la promesse des 3 secondes. Les chemins renvoyés sont rapprochés des vrais espaces (chemin exact, puis nom unique) ; espaces archivés exclus. Sans réponse d'espace du modèle, les candidats du routeur par mots-clés sont utilisés.
- Étape 6a : parser de secours. Intention : « rappelle-moi », « n'oublie pas », relance demandée → reminder ; « il faut que », « je dois », « à rendre », « devoir », « relancer », « finir », « préparer », « réviser »… → task ; sinon reminder si heure précise, task sinon. Espace : nom = 0,85, synonyme fort = 0,8, synonyme faible (« fin », « séance », « bug », « fields ») = 0,55, ancêtre trouvé aussi = +0,1, plusieurs branches = 0,5 max (question posée).
- Étape 6a : toast de capture en bas, au-dessus de la barre d'onglets, 6 s (10 s s'il pose la question). Sous-ligne = « jour heure · phrase dictée ». Sous le seuil, la tâche est créée sans espace et le toast propose les 3 meilleurs candidats, complétés par les espaces les plus utilisés puis les racines, plus « Aucun ».
- Étape 6a : tâche dictée sans date = créée directement (« sans date ») ; rappel dicté sans date = formulaire comme en V1. Widget « Prochain rappel » : rappels seulement. Réordonnancement du hub par appui long + glisser (`onMove`), archivage par balayage, section « Archivés » repliable avec Restaurer. Placeholders : colonne « Temps tracké » (6b), bloc Objectifs et lien Ajouter désactivé (6c), onglet Suivi (6b).
- Arguments DEBUG : `-uiTab day|month|spaces|tracking|settings`, `-uiSpace <nom>`, `-uiScreen capture|detail|form`, `-uiDictation "<phrase>"` (passe par le champ « Simuler une dictée »), `-parserSelfTest YES` (tableau dans la console), `-uiNoPrompt YES` (pas de demande d'autorisation des notifications, pour les captures).

## Tests à faire sur iPhone physique
Non vérifiables sur simulateur :
- Micro et transcription en direct (le simulateur reste sur « Micro inactif »), barre d'onde, reconnaissance on-device fr-FR.
- Foundation Models : Apple Intelligence est désactivé sur le Mac de dev, donc toutes les extractions testées viennent du parser de secours. Vérifier titres, dates (« jeudi prochain à 16h », « ce soir »…) et intervalles extraits par le modèle, et que la note de Réglages n'apparaît pas.
- Notifications : appui long sur la notification pour afficher Annuler / Fait sur l'écran verrouillé, relances réelles toutes les 5 / 15 / 30 / 60 min, son.
- Contrôle « Dicter un rappel » : le placer en bas de l'écran verrouillé (à la place de la lampe ou de l'appareil photo), vérifier tap → Face ID → app déjà en écoute.
- Widget « Prochain rappel » sur l'écran verrouillé : rendu, mise à jour après création / Fait / suppression, ouverture du détail au tap.
- Signature avec l'Apple ID gratuit : la capacité App Groups doit être acceptée par le profil de l'équipe personnelle (sinon, le widget « Prochain rappel » ne reçoit plus de données ; le contrôle reste fonctionnel quand l'intent s'exécute dans l'app).
- Appui long sur le micro vert (formulaire manuel) et retour haptique.
- Étape 6a : première ouverture avec le store V1 du téléphone, les rappels existants doivent réapparaître (sans espace) avec leurs notifications. Routage Foundation Models (intention, chemin, confiance) sur les 10 phrases de `ParserSelfTest` et des phrases réelles. Réordonnancement du hub par appui long, archivage par balayage, « Changer » et les puces du toast, cercle Fait dans le détail d'espace.
