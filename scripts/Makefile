# Makefile pour Athan Center
# Simplifie les commandes courantes

.PHONY: help quick install start stop restart logs build clean test setup deploy

# Afficher l'aide
help:
	@echo "🕌 Athan Center - Commandes Disponibles"
	@echo "========================================"
	@echo ""
	@echo "  make quick      - ⚡ Lancement rapide (docker-compose up -d)"
	@echo "  make install    - Installer les dépendances"
	@echo "  make setup      - Installation automatique complète"
	@echo "  make build      - Construire l'image Docker"
	@echo "  make start      - Démarrer l'application"
	@echo "  make stop       - Arrêter l'application"
	@echo "  make restart    - Redémarrer l'application"
	@echo "  make logs       - Afficher les logs"
	@echo "  make test       - Tester l'API"
	@echo "  make clean      - Nettoyer les fichiers générés"
	@echo "  make deploy     - Déployer en production"
	@echo "  make check      - Vérifier la configuration"
	@echo ""

# Lancement rapide
quick:
	@echo "⚡ Lancement rapide de Athan Center..."
	docker-compose up -d
	@echo "✓ Application démarrée!"
	@echo "📱 Accès: http://localhost:7777"

# Installer les dépendances Node.js
install:
	@echo "📦 Installation des dépendances..."
	npm install
	@echo "✓ Dépendances installées"

# Installation automatique complète
setup:
	@echo "🚀 Installation automatique..."
	chmod +x setup.sh
	./setup.sh

# Construire l'image Docker
build:
	@echo "🔨 Construction de l'image Docker..."
	docker-compose build
	@echo "✓ Image construite"

# Démarrer l'application
start:
	@echo "▶️  Démarrage de l'application..."
	docker-compose up -d
	@echo "✓ Application démarrée"
	@echo "📱 Accès: http://localhost:7777"

# Arrêter l'application
stop:
	@echo "⏹️  Arrêt de l'application..."
	docker-compose down
	@echo "✓ Application arrêtée"

# Redémarrer l'application
restart:
	@echo "🔄 Redémarrage de l'application..."
	docker-compose restart
	@echo "✓ Application redémarrée"

# Afficher les logs
logs:
	@echo "📋 Logs de l'application..."
	docker-compose logs -f

# Tester l'API
test:
	@echo "🧪 Tests de l'API..."
	chmod +x test-api.sh
	./test-api.sh

# Nettoyer
clean:
	@echo "🧹 Nettoyage..."
	docker-compose down -v
	rm -rf node_modules
	rm -f data/prayer.db
	@echo "✓ Nettoyage terminé"

# Déployer en production
deploy: build
	@echo "🚢 Déploiement en production..."
	docker-compose up -d --build
	@echo "✓ Déploiement terminé"
	@echo "📱 Accès: http://localhost:7777"

# Vérifier la configuration
check:
	@echo "✅ Vérification de la configuration..."
	@echo ""
	@echo "1. Vérification Docker..."
	@command -v docker >/dev/null 2>&1 && echo "  ✓ Docker installé" || echo "  ✗ Docker manquant"
	@command -v docker-compose >/dev/null 2>&1 && echo "  ✓ Docker Compose installé" || echo "  ✗ Docker Compose manquant"
	@echo ""
	@echo "2. Vérification des fichiers..."
	@test -f server.js && echo "  ✓ server.js présent" || echo "  ✗ server.js manquant"
	@test -f public/index.html && echo "  ✓ index.html présent" || echo "  ✗ index.html manquant"
	@test -f Dockerfile && echo "  ✓ Dockerfile présent" || echo "  ✗ Dockerfile manquant"
	@echo ""
	@echo "3. Vérification des dossiers..."
	@test -d audio && echo "  ✓ Dossier audio/ présent" || echo "  ✗ Dossier audio/ manquant"
	@test -d data && echo "  ✓ Dossier data/ présent" || echo "  ✗ Dossier data/ manquant"
	@echo ""
	@echo "4. Vérification audio..."
	@ls audio/*.mp3 >/dev/null 2>&1 && echo "  ✓ Fichiers audio trouvés" || echo "  ⚠ Aucun fichier audio (ajoutez athan.mp3)"
	@echo ""

# Backup
backup:
	@echo "💾 Sauvegarde..."
	@mkdir -p backups
	@tar -czf backups/athan-center-backup-$$(date +%Y%m%d_%H%M%S).tar.gz data/ audio/
	@echo "✓ Sauvegarde créée dans backups/"

# Restore (utiliser: make restore FILE=backup.tar.gz)
restore:
	@echo "📥 Restauration..."
	@test -n "$(FILE)" || (echo "Erreur: Spécifiez FILE=backup.tar.gz" && exit 1)
	@tar -xzf $(FILE)
	@echo "✓ Restauration terminée"

# Dev - Démarrer en mode développement
dev:
	@echo "🔧 Mode développement..."
	npm run dev

# Statistiques
stats:
	@echo "📊 Statistiques Docker..."
	docker stats athan-center --no-stream

# Informations système
info:
	@echo "ℹ️  Informations système..."
	@echo ""
	@echo "Docker version:"
	@docker --version
	@echo ""
	@echo "Docker Compose version:"
	@docker-compose --version
	@echo ""
	@echo "Node version:"
	@node --version 2>/dev/null || echo "Node non installé"
	@echo ""
	@echo "Espace disque:"
	@df -h . | tail -1
	@echo ""

# Shell dans le conteneur
shell:
	@echo "🐚 Ouverture du shell dans le conteneur..."
	docker exec -it athan-center /bin/bash

# Mise à jour
update:
	@echo "⬆️  Mise à jour..."
	git pull
	npm install
	docker-compose up -d --build
	@echo "✓ Mise à jour terminée"
