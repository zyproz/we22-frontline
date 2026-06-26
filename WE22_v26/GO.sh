#!/data/data/com.termux/files/usr/bin/bash
pkill -f server.py 2>/dev/null
pkill -f "localhost.run" 2>/dev/null
sleep 1

cd "$(dirname "$0")"

# Lancer le serveur (log dans le dossier home, pas /tmp)
python3 server.py > ~/fl22.log 2>&1 &
echo "Serveur démarré (PID $!)..."
sleep 3

# Vérifier que le serveur tourne
if ! kill -0 $! 2>/dev/null; then
  echo "ERREUR: serveur planté. Log:"
  cat ~/fl22.log
  exit 1
fi

echo "Connexion tunnel..."
ssh -o StrictHostKeyChecking=no -R 80:localhost:8080 nokey@localhost.run 2>&1 | while IFS= read -r line; do
  if echo "$line" | grep -q "https://"; then
    URL=$(echo "$line" | grep -oE 'https://[a-zA-Z0-9]+\.lhr\.life')
    if [ -n "$URL" ]; then
      echo ""
      echo "======================================="
      echo "  FRONTLINE 2022 -- BAKHMUT"
      echo "  LIEN: $URL"
      echo "======================================="
      echo ""
    fi
  fi
done
