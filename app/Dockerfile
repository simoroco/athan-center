FROM node:20-alpine

# Install dependencies for audio and build tools
RUN apk add --no-cache \
    alsa-utils \
    alsa-lib \
    alsa-plugins \
    alsa-plugins-pulse \
    sox \
    python3 \
    make \
    g++ && \
    # Configure sox to use ALSA directly (not libao)
    echo "Configuring audio drivers..."

# Création du répertoire de l'application
WORKDIR /app

# Copie des fichiers package.json
COPY package*.json ./

# Installation des dépendances Node.js
RUN npm install

# Copie de tous les fichiers de l'application
COPY . .

# Création des répertoires de destination (vides, seront montés via volume)
RUN mkdir -p /app/data /app/audio

# Copie des fichiers audio et data dans des dossiers "seed" pour initialisation
# IMPORTANT: Cette copie inclut TOUS les sous-dossiers: athan/, coran/, system/
RUN mkdir -p /app/audio_seed /app/data_seed && \
    echo "📂 Copying audio files to seed directory..." && \
    cp -rv audio/* /app/audio_seed/ && \
    echo "📂 Audio files copied. Contents:" && \
    ls -lR /app/audio_seed/ && \
    echo "📂 Copying data files to seed directory..." && \
    cp -rv data/* /app/data_seed/ 2>/dev/null || true && \
    echo "✅ Seed directories created successfully"

# Rendre le script d'entrypoint exécutable
RUN chmod +x /app/entrypoint.sh

# Exposition du port
EXPOSE 7777

# Utiliser l'entrypoint pour initialiser les volumes
ENTRYPOINT ["/app/entrypoint.sh"]

# Commande de démarrage
CMD ["node", "server.js"]
