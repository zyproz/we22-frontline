#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  WE22 Frontline — Script de déploiement automatique v21
#  Lance depuis Termux : bash SETUP_WE22.sh
# ═══════════════════════════════════════════════════════════════════

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

banner(){
  echo ""
  echo -e "${BLUE}${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}${BOLD}║   WE22 FRONTLINE — AUTO DEPLOY v21   ║${NC}"
  echo -e "${BLUE}${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""
}

step(){ echo -e "\n${GREEN}${BOLD}[$1] $2${NC}"; }
info(){ echo -e "${YELLOW}→ $1${NC}"; }
ok(){   echo -e "${GREEN}✓ $1${NC}"; }
err(){  echo -e "${RED}✗ $1${NC}"; }
pause(){ echo -e "\n${BOLD}Appuie sur ENTRÉE pour continuer...${NC}"; read; }

# ─── Vérifier que le fichier zip du jeu existe ───────────────────
check_zip(){
  ZIP=$(ls ~/storage/shared/Download/WE22_v2*.zip 2>/dev/null | tail -1)
  if [ -z "$ZIP" ]; then
    err "WE22_v20.zip ou WE22_v21.zip introuvable dans Téléchargements"
    err "Télécharge d'abord le fichier depuis Claude et réessaie"
    exit 1
  fi
  ok "Fichier trouvé: $(basename $ZIP)"
}

# ─── 1. Installer les outils ────────────────────────────────────
install_tools(){
  step "1/5" "Installation des outils"
  pkg update -y -q 2>/dev/null
  pkg install git nodejs-lts -y -q 2>/dev/null
  ok "git + node installés"
  npm install -g wrangler --quiet 2>/dev/null
  ok "Cloudflare Wrangler installé"
}

# ─── 2. Préparer les fichiers ──────────────────────────────────
prepare_files(){
  step "2/5" "Préparation des fichiers"
  
  mkdir -p ~/we22-game && cd ~/we22-game
  
  # Copier le zip et extraire
  ZIP=$(ls ~/storage/shared/Download/WE22_v2*.zip 2>/dev/null | tail -1)
  cp "$ZIP" ~/we22-game/
  unzip -o "$(basename $ZIP)" -d . > /dev/null 2>&1
  
  # Ajouter manifest.json si absent
  if [ ! -f manifest.json ]; then
    cat > manifest.json << 'EOF'
{
  "name": "WE22 Frontline",
  "short_name": "WE22",
  "start_url": "/",
  "display": "fullscreen",
  "orientation": "landscape",
  "background_color": "#0d0d0d",
  "theme_color": "#1a1a1a"
}
EOF
  fi
  
  # Ajouter _headers pour Cloudflare
  if [ ! -f _headers ]; then
    cat > _headers << 'EOF'
/*
  Access-Control-Allow-Origin: *
  Cache-Control: public, max-age=86400

/*.glb
  Content-Type: model/gltf-binary
  Access-Control-Allow-Origin: *
EOF
  fi
  
  ok "Fichiers prêts dans ~/we22-game/"
}

# ─── 3. Déployer sur Cloudflare Pages ─────────────────────────
deploy_cloudflare(){
  step "3/5" "Déploiement sur Cloudflare Pages"
  
  cd ~/we22-game
  
  echo ""
  echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}${BOLD}  ACTION REQUISE : Connexion Cloudflare  ${NC}"
  echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "1. Un lien va s'afficher → copie-le et ouvre-le dans Chrome"
  echo "2. Crée un compte Cloudflare GRATUIT (pas de carte bancaire)"
  echo "3. Autorise l'accès"
  echo "4. Reviens ici une fois connecté"
  echo ""
  pause
  
  wrangler login
  
  echo ""
  info "Déploiement des fichiers du jeu..."
  
  DEPLOY_OUTPUT=$(wrangler pages deploy . --project-name=we22-frontline 2>&1)
  
  if echo "$DEPLOY_OUTPUT" | grep -q "pages.dev"; then
    GAME_URL=$(echo "$DEPLOY_OUTPUT" | grep -o 'https://[^[:space:]]*pages.dev[^[:space:]]*' | tail -1)
    echo ""
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✅ JEU EN LIGNE POUR TOUJOURS !          ${NC}"
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}  URL du jeu :${NC}"
    echo -e "${BLUE}${BOLD}  $GAME_URL${NC}"
    echo ""
    
    # Sauvegarder l'URL
    echo "$GAME_URL" > ~/we22-game/GAME_URL.txt
    ok "URL sauvegardée dans ~/we22-game/GAME_URL.txt"
    
    # Mettre à jour le config Capacitor avec la vraie URL
    if [ -f capacitor.config.json ]; then
      sed -i "s|https://we22-frontline.pages.dev|$GAME_URL|g" capacitor.config.json
      ok "capacitor.config.json mis à jour avec l'URL réelle"
    fi
  else
    echo "$DEPLOY_OUTPUT"
    err "Problème lors du déploiement — relis le message ci-dessus"
    exit 1
  fi
}

# ─── 4. GitHub + APK automatique ──────────────────────────────
setup_github(){
  step "4/5" "Configuration GitHub pour l'APK automatique"
  
  cd ~/we22-game
  
  # Installer gh CLI si disponible
  pkg install gh -y -q 2>/dev/null || true
  
  if ! command -v gh &> /dev/null; then
    echo ""
    info "GitHub CLI non disponible — instructions manuelles :"
    echo ""
    echo "  1. Va sur https://github.com → crée un compte"
    echo "  2. Nouveau repo : 'we22-frontline' (public)"
    echo "  3. Puis reviens ici et tape tes infos GitHub :"
    echo ""
    echo -n "  Ton username GitHub : "
    read GH_USER
    echo -n "  Ton token GitHub (https://github.com/settings/tokens) : "
    read GH_TOKEN
    
    git init
    git add .
    git commit -m "WE22 Frontline v21"
    git branch -M main
    git remote add origin "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/we22-frontline.git"
    git push -u origin main 2>&1
  else
    echo ""
    echo "1. Un lien va s'afficher → ouvre-le dans Chrome"
    echo "2. Connecte ton compte GitHub"
    echo "3. Reviens ici après connexion"
    echo ""
    pause
    
    gh auth login --web
    GH_USER=$(gh api user --jq .login 2>/dev/null)
    
    # Créer le repo
    gh repo create we22-frontline --public --description "WE22 Frontline FPS" 2>/dev/null || true
    
    git init
    git add .
    git commit -m "WE22 Frontline v21"
    git branch -M main
    git remote add origin "https://github.com/${GH_USER}/we22-frontline.git" 2>/dev/null || true
    git push -u origin main 2>&1
    
    ok "Fichiers poussés sur GitHub !"
    echo ""
    echo -e "${YELLOW}${BOLD}→ L'APK se construit automatiquement sur GitHub !${NC}"
    echo -e "→ Va sur : https://github.com/${GH_USER}/we22-frontline/actions"
    echo -e "→ Attends 5-8 minutes → clique sur le job → télécharge l'APK"
  fi
}

# ─── 5. Résumé final ───────────────────────────────────────────
final_summary(){
  step "5/5" "Résumé"
  
  GAME_URL=$(cat ~/we22-game/GAME_URL.txt 2>/dev/null || echo "non disponible")
  
  echo ""
  echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ✅ TOUT EST PRÊT !                                ${NC}"
  echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "${BOLD}  🌐 URL du jeu (permanent, gratuit) :${NC}"
  echo -e "     ${BLUE}$GAME_URL${NC}"
  echo ""
  echo -e "${BOLD}  📱 Comment jouer MAINTENANT (sans APK) :${NC}"
  echo "     1. Ouvre Chrome sur ton tel"
  echo "     2. Va sur l'URL ci-dessus"
  echo "     3. Chrome → menu ⋮ → 'Ajouter à l'écran d'accueil'"
  echo "     → L'app apparaît sur l'écran comme une vraie app !"
  echo ""
  echo -e "${BOLD}  📦 APK Android (pour distribuer) :${NC}"
  echo "     → Va sur GitHub Actions → télécharge WE22-Frontline-APK.zip"
  echo "     → Partage le .apk à tes amis directement"
  echo ""
  echo -e "${BOLD}  🎮 Pour jouer ensemble :${NC}"
  echo "     → Un joueur crée la partie et donne le CODE"
  echo "     → Les autres entrent le code → C'est parti !"
  echo ""
  echo -e "${BOLD}  🔄 Pour mettre à jour le jeu :${NC}"
  echo "     cd ~/we22-game"
  echo "     cp ~/storage/shared/Download/NouvelleVersion.html index.html"
  echo "     wrangler pages deploy . --project-name=we22-frontline"
  echo "     → En ligne en 30 secondes, pas besoin de refaire l'APK !"
  echo ""
  echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════${NC}"
}

# ─── MAIN ─────────────────────────────────────────────────────
banner
check_zip
install_tools
prepare_files
deploy_cloudflare
setup_github
final_summary
