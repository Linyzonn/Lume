# 🎵 Lume — ton lecteur de musique iPhone

Lume est un lecteur de musique **local** pour iPhone : il lit **tes propres fichiers** (MP3, M4A, AAC, FLAC, WAV), sans pub, sans compte, sans connexion internet. Pensé pour ton usage : tu télécharges tes playlists en fichiers (Stacher 7 / yt-dlp), tu les mets sur l'iPhone, et Lume les lit.

## ✨ Ce que fait l'app

- 📥 Import de tes fichiers audio depuis l'app **Fichiers**
- 📚 Bibliothèque triée par **Titres / Albums / Artistes / Favoris**
- 🖼️ Pochettes d'album extraites automatiquement
- ▶️ Lecteur plein écran + mini-lecteur, **lecture en arrière-plan et écran verrouillé** (contrôles sur l'écran de verrouillage)
- 🔀 File d'attente, lecture aléatoire, répétition
- 📃 Playlists et favoris
- 🔎 Recherche
- 🎚️ **Égaliseur** 10 bandes avec préréglages (Basses+, Aigus+, Vocal, Pop, Rock, Électro…)
- 🔊 **Optimiseur de basses** réglable
- 🎤 **Ambiance / Concert** (réverbération : Pièce, Salle, Cathédrale, Concert) pour un rendu « live »
- 🎧 **Profils d'écoute** : Casque, Haut-parleur, Concert, Voix/Podcast, Normal — réglage automatique du son selon ton écoute
- 💬 **Paroles** (si elles sont intégrées au fichier)
- 🎵 **Crossfade** (fondu entre les morceaux)
- 🌙 **Minuteur de sommeil**

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

## Étape 4 — Mettre ta musique dans Lume

1. Transfère tes fichiers audio sur l'iPhone, au choix :
   - via **iCloud Drive** (tu les déposes depuis le PC, ils apparaissent dans l'app Fichiers), ou
   - via **Sideloadly** : coche **« App file sharing »** lors de l'install pour accéder au dossier de Lume depuis l'app Fichiers / le PC, ou
   - via un câble + l'Explorateur Windows (section partage de fichiers d'iTunes).
2. Dans **Lume**, touche le bouton **+** en haut à droite → **sélectionne tes fichiers** → ils s'importent avec pochette, titre et artiste.

---

# ⏳ Important : la limite des 7 jours

Avec un **Apple ID gratuit**, l'app cesse de fonctionner au bout de **7 jours** et tu peux installer **3 apps** maximum de cette façon. Pour repartir, il suffit de **relancer Sideloadly** (même Apple ID) pour la re-signer — **ta musique et tes playlists restent intactes**.

- Sideloadly propose une option **« auto-refresh »** (re-signature automatique) tant que l'iPhone et le PC sont sur le même Wi-Fi : pratique pour éviter de penser aux 7 jours.
- Un **compte développeur Apple payant (99 $/an)** étend la validité à **1 an** et lève la limite des 3 apps.

---

# 🧩 Dépannage rapide

- **« Unable to install / bundle ID »** : dans Sideloadly, change le **Bundle ID** (mets par exemple `com.tonprenom.lume`) puis relance.
- **L'app se ferme au lancement** : vérifie que tu as bien **« fait confiance »** au certificat (Étape 3d) et activé le **Mode développeur**.
- **L'iPhone n'apparaît pas dans Sideloadly** : vérifie les versions **web** d'iTunes/iCloud, et installe **Bonjour** (fourni avec iTunes) ; rebranche le câble.
- **Erreur de compilation sur GitHub** : copie le message et renvoie-le-moi.

---

# 🔧 Note technique (pour info)

- App **100 % SwiftUI**, cible **iOS 16+**, pensée pour iPhone 15 Pro.
- Moteur audio basé sur **AVAudioEngine** (nécessaire pour l'égaliseur et le crossfade).
- Le projet Xcode est généré à la volée par **XcodeGen** (`project.yml`) dans GitHub Actions, ce qui évite d'avoir à versionner un `.xcodeproj`.
- Le workflow compile **sans signature** ; c'est **Sideloadly** qui signe l'app avec ton Apple ID au moment de l'installation.

Bonne écoute ! 🎧
