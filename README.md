# 🎵 Lume — ton lecteur de musique iPhone

Lume est un lecteur de musique **local** pour iPhone : il lit **tes propres fichiers** (MP3, M4A, AAC, FLAC, WAV), sans pub et sans compte. **La lecture fonctionne 100 % hors connexion** — Internet ne sert qu'aux bonus : l'onglet **Découvrir** (recommandations), la récupération de pochettes, de photos d'artistes et de paroles en ligne.

## 🆕 Nouveautés 2.2

- 🔋 **Grosse économie de batterie** : le moteur audio et l'horloge interne ne tournent plus que pendant la lecture (avant, ils tournaient en permanence, même app en pause en arrière-plan), et l'écran verrouillé n'est plus mis à jour 4 fois par seconde.
- 🚀 **Défilement beaucoup plus fluide pendant la lecture** : la position du morceau ne réveille plus toute l'interface 4 fois par seconde — seuls le mini-lecteur, la barre de lecture et les paroles la suivent.
- ✨ **Découvrir se renouvelle vraiment** : le bouton Actualiser contourne désormais le cache, les artistes du profil tournent à chaque rafraîchissement (tirage pondéré), les titres sont piochés dans des viviers bien plus larges, et l'app **mémorise ce qu'elle t'a déjà proposé** pour ne pas te le resservir. Les titres déjà dans tes envies ne sont plus reproposés.
- 🎬 **Démarrage sans "saut" visuel** : l'écran de lancement se prolonge dans un écran d'accueil identique, le nom **Lume** apparaît, puis tout fond vers l'app.
- 🪪 **Identité renforcée** : glyphe et nom de l'app à l'accueil, dans une bibliothèque vide, au chargement de Découvrir et dans À propos.
- 🖼️ Les pochettes de Découvrir sont mises en cache (plus de re-téléchargement à chaque visite).
- 🔐 **Import Wi-Fi sécurisé** : un code à 4 chiffres (affiché dans Réglages, régénéré à chaque activation) est maintenant exigé — avant, n'importe qui sur le même Wi-Fi pouvait envoyer des fichiers dans l'app.
- 🧠 **Import Wi-Fi allégé** : les fichiers reçus sont écrits sur le disque au fil de la réception au lieu d'être accumulés en mémoire — les gros lots de FLAC ne risquent plus de faire fermer l'app en plein transfert.
- 🧹 Nettoyages automatiques : les playlists ne gardent plus de références vers des morceaux disparus, et le cache des réponses d'API est purgé des entrées de plus de 30 jours à chaque lancement.
- ⚡ Découvrir économise ~16 requêtes réseau par rafraîchissement quand le tri par tempo n'est pas possible.

## ✨ Ce que fait l'app (v2.0)

### Lecture
- ▶️ Lecteur plein écran + mini-lecteur, **lecture en arrière-plan et écran verrouillé**
- 🔗 **Enchaînement sans blanc (gapless)** : la piste suivante est préparée à l'avance
- 🎵 **Crossfade** (fondu entre les morceaux), qui fonctionne aussi en aléatoire
- 🔀 **Vrai mode aléatoire** : la file est mélangée une fois, aucun titre ne repasse avant que tous soient joués, « précédent » revient au bon morceau
- 📜 **File d'attente modifiable** : « Lire ensuite », « Ajouter à la file », réordonner et supprimer par glissement
- ⏩ **Vitesse de lecture** (0,75x à 2x, sans changer la hauteur du son) + sauts de 15 s — parfait pour les podcasts
- 📡 Bouton **AirPlay / sorties audio** dans le lecteur
- ⏸️ Pause automatique quand on **débranche les écouteurs**
- 🌙 **Minuteur de sommeil** avec fondu progressif du volume sur les 15 dernières secondes
- 💾 La position de lecture est sauvegardée en continu : même si iOS tue l'app, tu reprends où tu en étais

### Son
- 🎚️ **Égaliseur** 10 bandes avec préréglages (Basses+, Aigus+, Vocal, Pop, Rock, Électro…)
- 🎧 **Profils d'écoute** : Casque, Haut-parleur, Avion, Voiture, Concert, Voix/Podcast — et un bouton **« Personnalisé »** qui restaure tes réglages manuels
- 🔊 **Optimiseur de basses** et **boost de volume**, désormais protégés par un **limiteur** anti-saturation
- 🎤 **Ambiance / Concert** (réverbération : Pièce, Salle, Cathédrale, Concert)
- 🎛️ Tous les réglages audio sont **mémorisés** entre les lancements

### Bibliothèque
- 📶 **Import Wi-Fi** : active-le dans Réglages, ouvre l'adresse affichée dans le navigateur de ton PC, et glisse-dépose tes fichiers — **sans câble, sans iTunes**
- 📥 Import depuis l'app **Fichiers**, via iTunes/Finder (câble), ou **« Ouvrir avec Lume »** depuis n'importe quelle app
- 🧹 Les fichiers illisibles sont refusés à l'import **avec un message clair**
- 🖼️ Pochettes extraites automatiquement (ou récupérées en ligne), photos d'artistes
- 🤖 **Playlists intelligentes** : Ajoutés récemment, Top 25, Jamais écoutés, À redécouvrir
- 📃 Playlists, favoris, recherche, tri
- 📤 **Partage des fichiers d'une playlist** (AirDrop, Fichiers…) : ta musique n'est jamais prisonnière
- 💾 **Sauvegarde / restauration** : exporte un fichier JSON (playlists, favoris, paroles, stats, envies) et restaure-le après une réinstallation

### En ligne (facultatif)
- ✨ Onglet **Découvrir** : recommandations personnalisées selon tes écoutes (Deezer), extraits de 30 s, liste d'envies avec reconnaissance automatique à l'import
- 💬 **Paroles synchronisées** (LRC) trouvées en ligne, suivi en direct
- 📊 **Statistiques d'écoute** : totaux, activité 14 jours, série de jours consécutifs 🔥, tops titres/artistes

---

# 🛠️ Comment l'installer sur ton iPhone (depuis un PC Windows)

> ⚠️ **À savoir :** compiler une app iPhone nécessite un Mac. Comme tu es sur Windows, on utilise les **Mac gratuits dans le cloud de GitHub** pour fabriquer l'app, puis on l'installe avec **Sideloadly**. Aucun Mac nécessaire de ton côté.

La procédure a **3 étapes** : (1) déposer le projet sur GitHub, (2) le faire compiler en ligne pour récupérer le fichier `.ipa`, (3) l'installer sur l'iPhone avec Sideloadly.

Compte un petit **30–45 min la première fois**. Ensuite, réinstaller est très rapide.

---

## Étape 1 — Déposer le projet sur GitHub

1. Crée un compte gratuit sur **https://github.com** (si tu n'en as pas).
2. En haut à droite : **+ → New repository**.
   - Nom : `Lume` (par exemple)
   - Coche **Private** (privé, c'est mieux)
   - Ne coche rien d'autre, clique **Create repository**.
3. Sur la page du dépôt vide, clique **« uploading an existing file »** (ou **Add file → Upload files**).
4. **Glisse-dépose tout le contenu du dossier `Lume`** (le dossier `Sources`, le dossier `.github`, et le fichier `project.yml`).
   - 💡 Si l'interface web ne veut pas du dossier `.github` (les dossiers commençant par un point sont parfois cachés), le plus simple est d'installer **GitHub Desktop** (https://desktop.github.com) : tu y glisses le dossier complet et tu cliques **Commit** puis **Push**. Cela conserve l'arborescence exacte, ce qui est important.
5. Vérifie bien que l'arborescence sur GitHub ressemble à ça :
   ```
   Lume/
   ├── project.yml
   ├── .github/workflows/build.yml
   └── Sources/...
   ```

---

## Étape 2 — Compiler l'app en ligne (gratuit)

1. Sur ton dépôt GitHub, ouvre l'onglet **Actions**.
2. S'il demande d'autoriser les workflows : clique **« I understand my workflows, go ahead and enable them »**.
3. Dans la liste à gauche, clique sur **« Build IPA »**, puis à droite sur **Run workflow → Run workflow** (bouton vert).
4. Patiente **5 à 10 minutes** (un Mac compile l'app pour toi). Quand la coche devient verte ✅, clique sur le job terminé.
5. En bas de la page, section **Artifacts**, télécharge **`Lume-unsigned-ipa`**.
6. Tu obtiens un `.zip` : **dézippe-le**, tu y trouves **`Lume-unsigned.ipa`**. C'est ton app.

> Si la compilation échoue (croix rouge), ouvre le journal, copie l'erreur et **renvoie-la-moi** : je corrige le code et tu relances.

---

## Étape 3 — Installer le `.ipa` sur l'iPhone (Sideloadly)

### a) Préparer le PC

1. Installe **iTunes** et **iCloud** en **versions web d'Apple** (pas les versions du Microsoft Store).
   - Si tu as les versions du Microsoft Store, désinstalle-les d'abord, puis installe les versions classiques depuis le site d'Apple. *Sideloadly a besoin de ces versions web pour communiquer avec l'iPhone.*
2. Installe **Sideloadly** depuis **https://sideloadly.io** (Windows 10/11).

### b) Préparer l'iPhone

3. Sur l'iPhone : **Réglages → Confidentialité et sécurité → Mode développeur → activer**, puis redémarre l'iPhone et confirme.
   *(Apple impose le Mode développeur pour installer une app hors App Store sur iOS 16 et plus.)*

### c) Installer

4. Branche l'iPhone au PC en **USB**. Déverrouille-le et **« Faire confiance à cet ordinateur »**.
5. Ouvre **Sideloadly**. Ton iPhone doit apparaître en haut.
6. **Glisse `Lume-unsigned.ipa`** dans la fenêtre de Sideloadly.
7. Dans le champ **Apple ID**, mets ton adresse Apple (un Apple ID **gratuit** suffit).
8. Clique **Start**. Saisis ton mot de passe Apple (et un code de vérification si demandé).
   - 💡 Conseil : crée un Apple ID secondaire dédié à ça, pour ne pas mettre ton compte principal.
9. L'installation prend une minute ou deux. Lume apparaît ensuite sur l'écran d'accueil.

### d) Faire confiance au certificat (obligatoire)

10. Sur l'iPhone : **Réglages → Général → VPN et gestion de l'appareil → (ton Apple ID) → Faire confiance**.
11. Lance **Lume** 🎉

---

# 🎶 Étape 4 — Mettre ta musique dans Lume

### ⭐ Méthode recommandée : l'import Wi-Fi (sans câble)

1. Sur l'iPhone : **Lume → Réglages → Import Wi-Fi → activer**.
2. Une adresse s'affiche, du type `http://192.168.1.24:8080`.
3. Sur ton **PC** (connecté au **même Wi-Fi**), ouvre cette adresse dans le navigateur.
4. **Glisse-dépose tes fichiers audio** dans la page : ils arrivent directement dans Lume et s'importent tout seuls (pochette, titre, artiste).
5. Garde l'app Lume ouverte à l'écran pendant le transfert.

> 💡 Combo idéal avec **Stacher** : télécharge ta playlist sur le PC, puis glisse tout le dossier dans la page web. Fini le câble et iTunes.

### Autres méthodes

- **Depuis l'app Fichiers** : bouton **+** en haut à droite de l'onglet Musique → sélectionne tes fichiers (iCloud Drive fonctionne aussi).
- **« Ouvrir avec Lume »** : depuis Safari, Mail, Fichiers… partage un fichier audio → **Lume** → il s'importe.
- **Câble + iTunes/Finder** (l'ancienne méthode) : dépose les fichiers dans le dossier « Documents Lume » du partage de fichiers ; ils sont importés à l'ouverture de l'app.

---

# ⏳ Important : la limite des 7 jours

Avec un **Apple ID gratuit**, l'app cesse de fonctionner au bout de **7 jours** et tu peux installer **3 apps** maximum de cette façon. Pour repartir, il suffit de **relancer Sideloadly** (même Apple ID) pour la re-signer — **ta musique et tes playlists restent intactes**.

- Sideloadly propose une option **« auto-refresh »** (re-signature automatique) tant que l'iPhone et le PC sont sur le même Wi-Fi : pratique pour éviter de penser aux 7 jours.
- Un **compte développeur Apple payant (99 $/an)** étend la validité à **1 an** et lève la limite des 3 apps.
- 💾 Par précaution, exporte régulièrement une **sauvegarde** (Réglages → Sauvegarde) : même en cas de réinstallation complète, tu retrouves playlists, favoris et statistiques.

---

# 🧩 Dépannage rapide

- **« Unable to install / bundle ID »** : dans Sideloadly, change le **Bundle ID** (mets par exemple `com.tonprenom.lume`) puis relance.
- **L'app se ferme au lancement** : vérifie que tu as bien **« fait confiance »** au certificat (Étape 3d) et activé le **Mode développeur**.
- **L'iPhone n'apparaît pas dans Sideloadly** : vérifie les versions **web** d'iTunes/iCloud, et installe **Bonjour** (fourni avec iTunes) ; rebranche le câble.
- **L'import Wi-Fi ne s'ouvre pas sur le PC** : vérifie que l'iPhone et le PC sont sur le **même réseau Wi-Fi** (pas de partage de connexion 4G/5G), que Lume est **ouvert à l'écran**, et retape l'adresse exacte affichée (avec `:8080`).
- **Erreur de compilation sur GitHub** : copie le message et renvoie-le-moi.

---

# 🔧 Note technique (pour info)

- App **100 % SwiftUI**, cible **iOS 16+**, pensée pour iPhone 15 Pro.
- Moteur audio basé sur **AVAudioEngine** : double lecteur (crossfade/gapless), égaliseur, time-pitch (vitesse), limiteur de crête.
- Import Wi-Fi : mini serveur HTTP embarqué (**Network.framework**), aucun framework tiers.
- Le projet Xcode est généré à la volée par **XcodeGen** (`project.yml`) dans GitHub Actions, ce qui évite d'avoir à versionner un `.xcodeproj`.
- Le workflow compile **sans signature** ; c'est **Sideloadly** qui signe l'app avec ton Apple ID au moment de l'installation.

Bonne écoute ! 🎧
