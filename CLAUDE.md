# RemindersInt

## Vision
App iOS native de rappels à saisie vocale ultra-rapide. Le problème : les micro-tâches orales ("rappelle-moi d'appeler Karim") se perdent parce que les saisir dans Rappels ou Calendrier coûte trop cher sur le moment.
Promesse : capturer un rappel en moins de 3 secondes depuis l'écran verrouillé, et être relancé jusqu'à ce que ce soit fait.

## Utilisateur V1
Un seul utilisateur : le développeur, sur son iPhone 17 Pro Max, installé via Xcode avec un Apple ID gratuit. Pas d'App Store, pas de backend, pas de compte.

## Métrique de succès V1
Après une semaine d'usage réel : l'app est toujours utilisée chaque jour, et le nombre de rappels oubliés a baissé.

## Hors périmètre V1 (interdit tant que la V1 ne tourne pas)
Comptes, synchronisation, cloud, partage, Android, catégories, tags, pièces jointes, Siri, Apple Watch, widgets écran d'accueil autres que celui décrit, dark mode custom, onboarding, analytics, dépendances externes.

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
- Un seul modèle SwiftData : Reminder
  - id: UUID
  - title: String
  - dueDate: Date
  - repeatInterval: enum RepeatInterval { none, every5min, every15min, every30min, hourly }
  - status: enum ReminderStatus { pending, done, cancelled }
  - createdAt: Date
  - remindersSent: Int
  - rawTranscript: String? (ce qui a été dicté, pour debug)
- Services :
  - NotificationService : planifie, annule et replanifie les notifications locales selon repeatInterval, tant que status == pending
  - SpeechService : transcription voix -> texte
  - ParserService : texte -> Reminder via Foundation Models (titre, date/heure absolue, intervalle de relance). Date de référence = maintenant, en Europe/Paris, français. Si la date est absente, demander à l'utilisateur plutôt que d'inventer.

## Écrans (design validé, style Liquid Glass iOS 26)
1. Widget écran verrouillé : petit carré en verre avec icône micro, en bas à gauche. Un tap lance la capture vocale.
2. Capture vocale : panneau en verre par-dessus l'écran verrouillé. Indicateur "En écoute", transcription en direct, barre d'onde façon Dictée iOS, bouton vert en verre à droite pour valider. Après validation : le rappel est créé sans ouvrir l'app.
3. Notification : titre "Rappel", corps = titre du rappel, sous-ligne "Ne relance · prochaine dans X min". Deux actions directement sur la notif : Annuler (rouge) et Fait (vert).
4. Vue Jour (écran principal) : fond gris clair iOS avec légère teinte, cartes en verre blanc. En haut "MARDI 29 SEPT." puis "Aujourd'hui" en gros, bouton calendrier à droite. Sélecteur de 5 jours (jour courant en noir). Liste des rappels : heure en gras, titre, sous-ligne de relance, icône de statut (refresh si pending, check vert si done, barré et grisé si done). Barre d'onglets flottante en verre (Jour / Calendrier / Réglages) avec gros bouton micro vert à droite.
5. Vue Mois : grille du mois dans une carte en verre, point vert sous les jours qui ont des rappels, jour sélectionné en noir, liste des rappels du jour sélectionné dessous, lien "Voir la journée".

Palette : fond #F2F2F7, texte #1C1C1E, secondaire #6E6E73, vert #34C759, rouge #FF453A, cartes blanches translucides avec .glassEffect() quand dispo, sinon .ultraThinMaterial. Police système (SF). Coins 20 à 28 pt. Pas d'emoji.

## Règles de travail
- Avancer par étapes, une fonctionnalité à la fois, un commit par étape.
- Le projet doit compiler sans warning et tourner sur simulateur ET sur iPhone physique à la fin de chaque étape.
- Ne jamais ajouter de fonctionnalité hors périmètre V1 sans demande explicite.
- Si une API iOS 26 n'est pas disponible ou incertaine (Foundation Models, glassEffect), le dire clairement et proposer le fallback le plus simple plutôt que de contourner en silence.
- Code et commentaires en anglais, textes UI en français.

## Plan
- [x] Étape 1 : modèle SwiftData + Vue Jour + Vue Mois + ajout/édition manuelle + Fait/Annulé. Pas de notif, pas de voix, pas de widget.
- [x] Étape 2 : NotificationService + relances + actions Fait/Annulé sur la notification.
- [x] Étape 3 : SpeechService + ParserService (Foundation Models) + écran de capture vocale dans l'app.
- [x] Étape 4 : widget écran verrouillé + App Intent qui ouvre la capture vocale.
- [ ] Étape 5 : polish Liquid Glass et tests sur une semaine d'usage.

## Décisions prises en cours de route
- Étape 2 : compteur remindersSent = notifications délivrées, première incluse (libellé « Notifications envoyées »). Rattrapage app fermée par calcul des heures passées. Suppression : swipe complet à gauche (avec confirmation) et bouton dans le détail.
- Étape 3 : `Date` n'est pas `@Generable`, le modèle renvoie une date ISO `AAAA-MM-JJTHH:MM` convertie ensuite. Parser de secours en Swift pur si Foundation Models est indisponible ou échoue (note dans Réglages). Champ « Simuler une dictée » en DEBUG uniquement.
- Étape 4 : option A retenue, un ControlWidget (`ControlWidgetButton` + `StartVoiceCaptureIntent`, `openAppWhenRun`) placé en bas de l'écran verrouillé ou dans le Centre de contrôle. Vérifié sur simulateur via le Centre de contrôle : un tap lance l'app fermée directement sur la dictée. iOS impose le premier plan pour le micro : depuis l'écran verrouillé, le tap déclenche Face ID puis l'app s'ouvre déjà en écoute ; il n'existe pas de dictée sans déverrouiller.
- Étape 4 : deep links `remindersint://capture` et `remindersint://reminder/<uuid>`. Widget `accessoryRectangular` « Prochain rappel » alimenté par un instantané JSON écrit par l'app dans l'App Group `group.com.yacine.RemindersInt` (le widget ne lit pas SwiftData). Code commun app/extension dans `Shared/`.

## Tests à faire sur iPhone physique
Non vérifiables sur simulateur :
- Micro et transcription en direct (le simulateur reste sur « Micro inactif »), barre d'onde, reconnaissance on-device fr-FR.
- Foundation Models : Apple Intelligence est désactivé sur le Mac de dev, donc toutes les extractions testées viennent du parser de secours. Vérifier titres, dates (« jeudi prochain à 16h », « ce soir »…) et intervalles extraits par le modèle, et que la note de Réglages n'apparaît pas.
- Notifications : appui long sur la notification pour afficher Annuler / Fait sur l'écran verrouillé, relances réelles toutes les 5 / 15 / 30 / 60 min, son.
- Contrôle « Dicter un rappel » : le placer en bas de l'écran verrouillé (à la place de la lampe ou de l'appareil photo), vérifier tap → Face ID → app déjà en écoute.
- Widget « Prochain rappel » sur l'écran verrouillé : rendu, mise à jour après création / Fait / suppression, ouverture du détail au tap.
- Signature avec l'Apple ID gratuit : la capacité App Groups doit être acceptée par le profil de l'équipe personnelle (sinon, le widget « Prochain rappel » ne reçoit plus de données ; le contrôle reste fonctionnel quand l'intent s'exécute dans l'app).
- Appui long sur le micro vert (formulaire manuel) et retour haptique.
