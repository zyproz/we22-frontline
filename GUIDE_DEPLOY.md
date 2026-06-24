# WE22 Frontline — Guide déploiement v21

## Architecture finale
```
Cloudflare Pages → sert index.html + Soldier.glb (GRATUIT, TOUJOURS EN LIGNE)
         ↓
Ably Cloud → synchronise les joueurs en temps réel (DÉJÀ INTÉGRÉ)
         ↓
APK Android → ouvre l'URL Cloudflare dans une WebView native
```

---

## ÉTAPE 1 — Héberger le jeu sur Cloudflare Pages (5 min)

### 1a. Créer un compte GitHub
- Va sur https://github.com
- Crée un compte (gratuit)

### 1b. Créer un repo et uploader les fichiers

**Depuis Termux** :
```bash
pkg install git -y

# Configurer git
git config --global user.name "TonNom"
git config --global user.email "ton@email.com"

# Créer le repo local
mkdir ~/we22-deploy && cd ~/we22-deploy
cp ~/storage/shared/Download/WE22_v21/* . -r 2>/dev/null || true

git init
git add .
git commit -m "WE22 Frontline v21"

# Créer le repo sur GitHub (via l'API)
# Va sur https://github.com/new → crée "we22-frontline" (public)
# Puis :
git remote add origin https://github.com/TON_USERNAME/we22-frontline.git
git branch -M main
git push -u origin main
```

### 1c. Déployer sur Cloudflare Pages
1. Va sur https://dash.cloudflare.com (créer compte GRATUIT, pas de carte bancaire)
2. **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
3. Choisir ton repo `we22-frontline`
4. Paramètres de build :
   - **Framework preset** : `None`
   - **Build command** : *(laisser vide)*
   - **Build output directory** : `/` (racine)
5. Cliquer **Save and Deploy**

→ Tu obtiens une URL permanente : `https://we22-frontline.pages.dev`

---

## ÉTAPE 2 — Mettre à jour l'URL dans le config

Dans `capacitor.config.json`, remplace :
```json
"url": "https://we22-frontline.pages.dev"
```
par ton URL Cloudflare réelle.

Puis commit et push :
```bash
cd ~/we22-deploy
git add capacitor.config.json
git commit -m "Update Cloudflare URL"
git push
```

---

## ÉTAPE 3 — Obtenir l'APK via GitHub Actions (automatique)

Après chaque `git push` :
1. Va sur `https://github.com/TON_USERNAME/we22-frontline`
2. Clique sur l'onglet **Actions**
3. Tu vois le workflow **Build WE22 APK** qui tourne (~5-8 min)
4. Une fois terminé, clique dessus → **Artifacts** → **WE22-Frontline-APK.zip**
5. Télécharge et partage le fichier `app-debug.apk`

---

## ÉTAPE 4 — Installer l'APK sur les téléphones

Sur chaque téléphone ami :
1. **Paramètres** → **Sécurité** → Activer **Sources inconnues**
2. Installer `app-debug.apk`
3. L'icône **WE22 Frontline** apparaît dans les apps

---

## Comment jouer

1. Ouvrir l'app WE22
2. Choisir sa faction (🇺🇦 ou 🇷🇺)
3. Un joueur clique **CRÉER UNE PARTIE** → note le code (ex: `FKMK8T`)
4. Les autres cliquent **REJOINDRE** et tapent le code
5. ✅ La partie commence !

**Aucun serveur local à lancer** — tout passe par Cloudflare (jeu) + Ably (multi).

---

## FAQ

**Le jeu est-il toujours disponible ?**
Oui, Cloudflare Pages est gratuit et toujours en ligne. Aucun téléphone ne doit rester allumé.

**Peut-on le couper ?**
Oui : Cloudflare Dashboard → ton projet → **Settings** → **Disable Production Deployments**

**Comment mettre à jour le jeu ?**
Modifie `index.html` dans le repo GitHub → `git push` → Cloudflare redéploie automatiquement (~1 min). L'APK n'a pas besoin d'être refait.

**L'APK expire ?**
L'APK debug est valide 90 jours sur GitHub Actions. Re-run le workflow pour en avoir un nouveau.

---

## Commandes rapides Termux

```bash
# Première installation
pkg install git -y

# Pousser une mise à jour du jeu
cd ~/we22-deploy
cp ~/storage/shared/Download/index.html .
git add index.html
git commit -m "Update game"
git push
# → Cloudflare redéploie automatiquement en 1 minute
```
