# Makefile for Athan Center
# Simplifies common commands

.PHONY: help quick install start stop restart logs build clean test setup deploy

# Show help
help:
	@echo "🕌 Athan Center - Available Commands"
	@echo "========================================"
	@echo ""
	@echo "  make quick      - ⚡ Quick launch (docker-compose up -d)"
	@echo "  make install    - Install dependencies"
	@echo "  make setup      - Full automatic installation"
	@echo "  make build      - Build the Docker image"
	@echo "  make start      - Start the application"
	@echo "  make stop       - Stop the application"
	@echo "  make restart    - Restart the application"
	@echo "  make logs       - Show logs"
	@echo "  make test       - Test the API"
	@echo "  make clean      - Remove generated files"
	@echo "  make deploy     - Deploy to production"
	@echo "  make check      - Check the configuration"
	@echo ""

# Quick launch
quick:
	@echo "⚡ Quick launch of Athan Center..."
	docker-compose up -d
	@echo "✓ Application started!"
	@echo "📱 Access: http://localhost:7777"

# Install Node.js dependencies
install:
	@echo "📦 Installing dependencies..."
	npm install
	@echo "✓ Dependencies installed"

# Full automatic installation
setup:
	@echo "🚀 Automatic installation..."
	chmod +x setup.sh
	./setup.sh

# Build the Docker image
build:
	@echo "🔨 Building the Docker image..."
	docker-compose build
	@echo "✓ Image built"

# Start the application
start:
	@echo "▶️  Starting the application..."
	docker-compose up -d
	@echo "✓ Application started"
	@echo "📱 Access: http://localhost:7777"

# Stop the application
stop:
	@echo "⏹️  Stopping the application..."
	docker-compose down
	@echo "✓ Application stopped"

# Restart the application
restart:
	@echo "🔄 Restarting the application..."
	docker-compose restart
	@echo "✓ Application restarted"

# Show logs
logs:
	@echo "📋 Application logs..."
	docker-compose logs -f

# Test the API
test:
	@echo "🧪 Testing the API..."
	chmod +x test-api.sh
	./test-api.sh

# Clean up
clean:
	@echo "🧹 Cleaning up..."
	docker-compose down -v
	rm -rf node_modules
	rm -f data/prayer.db
	@echo "✓ Cleanup finished"

# Deploy to production
deploy: build
	@echo "🚢 Deploying to production..."
	docker-compose up -d --build
	@echo "✓ Deployment finished"
	@echo "📱 Access: http://localhost:7777"

# Check the configuration
check:
	@echo "✅ Checking the configuration..."
	@echo ""
	@echo "1. Checking Docker..."
	@command -v docker >/dev/null 2>&1 && echo "  ✓ Docker installed" || echo "  ✗ Docker missing"
	@command -v docker-compose >/dev/null 2>&1 && echo "  ✓ Docker Compose installed" || echo "  ✗ Docker Compose missing"
	@echo ""
	@echo "2. Checking files..."
	@test -f server.js && echo "  ✓ server.js present" || echo "  ✗ server.js missing"
	@test -f public/index.html && echo "  ✓ index.html present" || echo "  ✗ index.html missing"
	@test -f Dockerfile && echo "  ✓ Dockerfile present" || echo "  ✗ Dockerfile missing"
	@echo ""
	@echo "3. Checking folders..."
	@test -d audio && echo "  ✓ audio/ folder present" || echo "  ✗ audio/ folder missing"
	@test -d data && echo "  ✓ data/ folder present" || echo "  ✗ data/ folder missing"
	@echo ""
	@echo "4. Checking audio..."
	@ls audio/*.mp3 >/dev/null 2>&1 && echo "  ✓ Audio files found" || echo "  ⚠ No audio files (add athan.mp3)"
	@echo ""

# Backup
backup:
	@echo "💾 Backing up..."
	@mkdir -p backups
	@tar -czf backups/athan-center-backup-$$(date +%Y%m%d_%H%M%S).tar.gz data/ audio/
	@echo "✓ Backup created in backups/"

# Restore (use: make restore FILE=backup.tar.gz)
restore:
	@echo "📥 Restoring..."
	@test -n "$(FILE)" || (echo "Error: Specify FILE=backup.tar.gz" && exit 1)
	@tar -xzf $(FILE)
	@echo "✓ Restore finished"

# Dev - Start in development mode
dev:
	@echo "🔧 Development mode..."
	npm run dev

# Statistics
stats:
	@echo "📊 Docker statistics..."
	docker stats athan-center --no-stream

# System information
info:
	@echo "ℹ️  System information..."
	@echo ""
	@echo "Docker version:"
	@docker --version
	@echo ""
	@echo "Docker Compose version:"
	@docker-compose --version
	@echo ""
	@echo "Node version:"
	@node --version 2>/dev/null || echo "Node not installed"
	@echo ""
	@echo "Disk space:"
	@df -h . | tail -1
	@echo ""

# Shell into the container
shell:
	@echo "🐚 Opening container shell..."
	docker exec -it athan-center /bin/bash

# Update
update:
	@echo "⬆️  Updating..."
	git pull
	npm install
	docker-compose up -d --build
	@echo "✓ Update finished"
