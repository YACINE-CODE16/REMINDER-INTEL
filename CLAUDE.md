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
  - Session (étape 6b) : id, space (toujours renseigné ; optionnel côté SwiftData), startedAt, endedAt?, note?, rawTranscript?. Une seule session ouverte (endedAt == nil) à la fois. Une session fermée ne passe jamais minuit : elle est coupée à la clôture, à l'enregistrement et à la modification.
  - Goal (étape 6c) : id, space (toujours renseigné), title, kind { hours, count, outcome }, target, unit?, period { week, month, untilDate, none }, deadline?, currentManual, counterPeriodStart?, isAchieved, achievedAt?, createdAt, isArchived, steps: [GoalStep { id, title, isDone, sortOrder }]. Calculs dans `GoalMath`.
  - Reminder : modèle V1 conservé uniquement comme stockage hérité, vidé au lancement par `StoreSetup` (voir Décisions).
- Services :
  - NotificationService : planifie, annule et replanifie les notifications locales des TaskItem en attente et datés ; relances selon repeatInterval pour les rappels, notification unique pour les tâches
  - SpeechService : transcription voix -> texte
  - ParserService : texte -> ParsedCapture via Foundation Models : intention (reminder / task ; session et goal prévus, non produits), titre, date/heure absolue, intervalle de relance, jusqu'à 3 espaces probables avec confiance. Date de référence = maintenant, en Europe/Paris, français. Un rappel sans date fait demander la date plutôt que d'inventer ; une tâche peut rester sans date.
  - SpaceRouter : routage de secours par mots-clés sur les noms d'espaces et leurs synonymes. Seuil de confiance 0,6.
  - TrackingService : démarrer / arrêter / enregistrer / modifier une session, Live Activity (ActivityKit, mise à jour locale), notification « Toujours sur … ? » après 4 h, rappel « Rien tracké aujourd'hui » à 20 h.

## Écrans (design validé, style Liquid Glass iOS 26)
1. Widget écran verrouillé : petit carré en verre avec icône micro, en bas à gauche. Un tap lance la capture vocale.
2. Capture vocale : panneau en verre par-dessus l'écran verrouillé. Indicateur "En écoute", transcription en direct, barre d'onde façon Dictée iOS, bouton vert en verre à droite pour valider. Après validation : le rappel est créé sans ouvrir l'app.
3. Notification : titre "Rappel", corps = titre du rappel, sous-ligne "Ne relance · prochaine dans X min". Deux actions directement sur la notif : Annuler (rouge) et Fait (vert).
4. Vue Jour (écran principal) : fond gris clair iOS avec légère teinte, cartes en verre blanc. En haut "MARDI 29 SEPT." puis "Aujourd'hui" en gros, boutons calendrier et engrenage (Réglages) à droite. Sélecteur de 5 jours (jour courant en noir). Liste des rappels et tâches datés : heure en gras, trait de la couleur de l'espace (neutre sans espace), titre, sous-ligne espace · relance, icône de statut (refresh si rappel en attente, cercle si tâche à faire, check vert si done, barré et grisé si annulé). Barre d'onglets flottante en verre (Jour / Calendrier / Espaces / Suivi) avec gros bouton micro vert à droite.
5. Vue Mois : grille du mois dans une carte en verre, point vert sous les jours qui ont des rappels, jour sélectionné en noir, liste des rappels du jour sélectionné dessous (même carte que la Vue Jour, couleur d'espace), lien "Voir la journée".
6. Vue Suivi (onglet Suivi) : en-tête "MERCREDI 14 OCT." + "Suivi" 34 pt bold, bouton stats (icône barres) en verre en haut à droite. Carte noire pleine coins 28 pt avec ombre : pastille icône de l'espace à gauche, "EN COURS · ÉTUDES" en 12 pt à 70 %, chrono 30 pt bold tabulaire, bouton Stop rouge #FF453A 52 pt coins 18 pt avec carré blanc. Sans session active : même carte en verre avec "Démarrer" et les 3 espaces récents en puces. Section "Aujourd'hui" avec total à droite ("4h10 au total") : une carte en verre par espace racine ayant du temps aujourd'hui = point couleur 10 pt, nom 15 pt semibold, temps en bold, "/ 20h sem." en gris si objectif hebdo, barre 6 pt couleur de l'espace. Section "Sessions" avec lien "Ajouter" bleu : lignes en verre léger = plage horaire 13 pt gris sur 92 pt, trait vertical, "Espace · note" 14 pt semibold, durée en bold à droite. Barre d'onglets avec Suivi actif.
7. Statistiques : bouton retour, titre "Statistiques" 22 pt, bascule 7 jours / 30 jours en capsule (actif noir). Carte en verre : anneau 120 pt (SectorMark, 4 à 5 espaces, épaisseur 16) avec total "31h" + "cette semaine" au centre, légende à droite (point couleur, nom, durée bold). Carte "Par jour" avec "moy. 4h25" : 7 barres empilées par espace, hauteur 110 pt, coins 6 pt, le jour courant en bordure pointillée, lettres des jours dessous. Deux tuiles : "Série Études 12 j, record personnel" en vert, "Objectifs atteints 2 / 4" (placeholder jusqu'à 6c).
8. Session en cours sur écran verrouillé (Live Activity) : même carte en verre que la notification de rappel : pastille couleur de l'espace avec icône, "ÉTUDES · TAGE MAGE" 12 pt à 75 %, chrono 30 pt bold, bouton Stop rouge translucide 52 pt. Dynamic Island compacte : icône espace + chrono.
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
- [x] Étape 6b : Suivi du temps (sessions par espace, onglet Suivi, statistiques, Live Activity, « Temps tracké » du hub, intentions de session).
- [x] Étape 6c : Objectifs par espace (bloc Objectifs, objectif le plus urgent dans le hub, cibles hebdo dans Suivi, tuile et vue d'ensemble dans les stats, pastille « Objectif » dans la Vue Jour, intention `goalProgress`).

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
- Étape 6a : après « il faut que je / j' », le parser de secours remet le premier verbe à l'infinitif via une table de 30 verbes courants (finisse → finir, envoie → envoyer…) ; hors table, le mot reste tel quel.
- Étape 6a : toast de capture en bas, au-dessus de la barre d'onglets, 6 s (10 s s'il pose la question). Sous-ligne = « jour heure · phrase dictée ». Sous le seuil, la tâche est créée sans espace et le toast propose les 3 meilleurs candidats, complétés par les espaces les plus utilisés puis les racines, plus « Aucun ».
- Étape 6a : tâche dictée sans date = créée directement (« sans date ») ; rappel dicté sans date = formulaire comme en V1. Widget « Prochain rappel » : prochain élément daté, rappel ou tâche, préfixé « Rappel · » ou « Tâche · » (`WidgetSnapshot.Item.isReminder` optionnel pour relire les anciens instantanés). Réordonnancement du hub par appui long + glisser (`onMove`), archivage par balayage, section « Archivés » repliable avec Restaurer. Placeholders : colonne « Temps tracké » (6b), bloc Objectifs et lien Ajouter désactivé (6c), onglet Suivi (6b).
- Étape 6b : `Session.space` est optionnel dans le modèle (une relation to-one non optionnelle est fragile avec SwiftData et la suppression en cascade depuis Space) mais toujours renseigné par l'app. Démarrer une session clôt la précédente. Les sessions qui se chevauchent ne sont pas fusionnées (un log dicté sur une plage déjà trackée s'additionne).
- Étape 6b : Live Activity mise à jour localement (pas de push). Le chrono est un `Text(timerInterval:)` système, aucune mise à jour périodique. Stop = `StopSessionIntent` (`LiveActivityIntent`, exécuté dans le processus de l'app via le crochet `SessionControl.stop`) ; si le crochet est absent, la demande est déposée dans l'App Group et appliquée au retour au premier plan (`TrackingService.resume`). Au lancement et au retour au premier plan, l'activité est recréée ou fermée selon le store. Tap sur l'activité = `remindersint://tracking`.
- Étape 6b : voix. `sessionStart` (« je commence », « je me mets sur », « je démarre », « c'est parti »… sans date), `sessionStop` (« stop », « j'arrête », « fini », « pause »… phrase de 4 mots max ou contenant « session »), `sessionLog` (« j'ai fait / bossé / révisé… » + durée « 2h », « 1h30 », « 45 min », « une heure et demie »). Durée extraite avant la date pour que « 2h » ne soit pas lu comme 02:00. Moment : « ce matin » = 09:00, « hier soir » = 19:00 la veille ; sans moment, la session finit maintenant ; une session passée ne finit jamais dans le futur. Une session sans espace sûr demande l'espace dans le toast (sans « Aucun ») et n'est créée qu'au choix.
- Étape 6b : « Toujours sur … ? » 4 h après le début ; « Continuer » reprogramme 2 h plus tard, « Arrêter maintenant » clôt. « Rien tracké aujourd'hui » : notifications non répétées à 20 h pour les 7 prochains jours, celle du jour retirée dès qu'une session existe ; activé par défaut, interrupteur « Rappel du soir » dans Réglages.
- Étape 6b : stats. « 7 jours » et « 30 jours » sont glissants, aujourd'hui inclus (« 7 derniers jours », « 30 derniers jours ») ; moyenne = total / 7 ou 30 ; anneau et barres suivent. La semaine calendaire lundi-dimanche reste pour le hub et les objectifs hebdo. Anneau : 5 racines max, au-delà 4 + « Autres ». Série = plus longue suite de jours consécutifs (jusqu'à aujourd'hui ou hier) d'un espace racine ; « record personnel » si elle égale le record. Tuile Objectifs en placeholder (6c). Hub : « Temps tracké » = semaine en cours, delta vs semaine dernière au même moment.
- Étape 6c : champs ajoutés au modèle demandé : `isAchieved` / `achievedAt` (état atteint coché d'un outcome) et `counterPeriodStart` (un compteur hebdo ou mensuel repart de 0 à la période suivante, remise à zéro paresseuse à la lecture et au +1). Un outcome est enregistré avec `period = untilDate` et `target = 1`.
- Étape 6c : progression. hours = sessions de l'espace et de ses descendants sur la fenêtre (semaine calendaire lundi-dimanche, mois calendaire, création → échéance, ou création → maintenant). count = compteur de la période en cours. outcome = étapes faites / total pour la barre du hub ; atteint seulement quand l'utilisateur le coche. Vérifié sur la semaine du 28 sept. au 4 oct. 2026 avec une session coupée à minuit (self-test).
- Étape 6c : urgence = échéances non atteintes d'abord (la plus proche en tête), puis les objectifs périodiques les plus en retard sur leur rythme (part de la période écoulée − progression), les atteints en dernier. Le hub montre l'objectif le plus urgent du sous-arbre, sur toute la largeur de la carte.
- Étape 6c : le détail d'espace est une `List` : une carte de verre par objectif (et non une seule carte à lignes) pour le balayage « Archiver » natif. Tap sur le libellé = formulaire (modification, compteur ajustable, sous-étapes, archiver). « / Xh sem. » dans Suivi = somme des objectifs hours hebdo de la racine et de ses descendants. Pastille « Objectif » dans la Vue Jour : outcome non atteint dont l'échéance tombe dans les 7 jours, sur l'espace de la tâche ou un ancêtre.
- Étape 6c : tuile « Objectifs atteints n / m » : objectifs hebdo, mensuels et sans période évalués maintenant ; objectifs datés comptés si leur échéance n'est pas antérieure à la période affichée ou s'ils ont été atteints pendant. Tap = `GoalsOverview` (objectifs actifs groupés par espace, par urgence).
- Étape 6c : voix `goalProgress` (« j'ai signé », « … de plus », « encore un », « séance faite », « plus un », « +1 », sans date). Choix du compteur : un mot de 4 lettres ou plus du titre ou de l'unité dans la phrase (pluriel ignoré), sinon les espaces devinés (même sous le seuil), sinon tous les compteurs. Un seul candidat = +1 et toast avec « Annuler » (retire le +1) ; plusieurs = « Quel objectif ? » avec 4 puces max ; aucun = « Aucun objectif compteur ».
- Arguments DEBUG : `-seedDemoGoals YES` (3 objectifs de chaque type, une fois), `-uiDayOffset <n>`, `-seedDemoSessions YES` (deux semaines de sessions, une fois), `-uiTab day|month|spaces|tracking|stats|settings`, `-uiSpace <nom>`, `-uiScreen capture|detail|form`, `-uiDictation "<phrase>"` (passe par le champ « Simuler une dictée »), `-parserSelfTest YES` (tableau dans la console), `-uiNoPrompt YES` (pas de demande d'autorisation des notifications, pour les captures).

## Tests à faire sur iPhone physique
Non vérifiables sur simulateur :
- Micro et transcription en direct (le simulateur reste sur « Micro inactif »), barre d'onde, reconnaissance on-device fr-FR.
- Foundation Models : Apple Intelligence est désactivé sur le Mac de dev, donc toutes les extractions testées viennent du parser de secours. Vérifier titres, dates (« jeudi prochain à 16h », « ce soir »…) et intervalles extraits par le modèle, et que la note de Réglages n'apparaît pas.
- Notifications : appui long sur la notification pour afficher Annuler / Fait sur l'écran verrouillé, relances réelles toutes les 5 / 15 / 30 / 60 min, son.
- Contrôle « Dicter un rappel » : le placer en bas de l'écran verrouillé (à la place de la lampe ou de l'appareil photo), vérifier tap → Face ID → app déjà en écoute.
- Widget « Prochain rappel » sur l'écran verrouillé : rendu avec préfixe « Rappel · » / « Tâche · », mise à jour après création / Fait / suppression, ouverture du détail au tap.
- Signature avec l'Apple ID gratuit : la capacité App Groups doit être acceptée par le profil de l'équipe personnelle (sinon, le widget « Prochain rappel » ne reçoit plus de données ; le contrôle reste fonctionnel quand l'intent s'exécute dans l'app).
- Appui long sur le micro vert (formulaire manuel) et retour haptique.
- Étape 6c : +1 et Annuler du toast au doigt, cercle atteint et sous-étapes, balayage « Archiver », formulaire d'objectif (segmented, unité, période, échéance, étapes), routage Foundation Models des phrases goalProgress.
- Étape 6b : Live Activity sur l'écran verrouillé (non capturable automatiquement au simulateur : Cmd-L dans Simulator), Dynamic Island étendue, bouton Stop de l'activité app fermée, notification « Toujours sur … ? » avec Continuer / Arrêter maintenant, rappel de 20 h, routage Foundation Models des phrases de session.
- Étape 6a : première ouverture avec le store V1 du téléphone, les rappels existants doivent réapparaître (sans espace) avec leurs notifications. Routage Foundation Models (intention, chemin, confiance) sur les 10 phrases de `ParserSelfTest` et des phrases réelles. Réordonnancement du hub par appui long, archivage par balayage, « Changer » et les puces du toast, cercle Fait dans le détail d'espace.
