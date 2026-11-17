FROM node:20-alpine

# Install audio dependencies for Linux (Sox + ALSA)
RUN echo "Installing audio dependencies..." && \
    apk add --no-cache \
    sox \
    alsa-utils \
    alsa-lib \
    alsa-plugins-pulse \
    openssl \
    && echo "✅ Audio & SSL dependencies installed successfully"

# Create the application directory
WORKDIR /app

# Copy package.json files
COPY package*.json ./

# Install Node.js dependencies
RUN npm install

# Copy all application files
COPY . .

# Create destination directories (empty, will be mounted via volume)
RUN mkdir -p /app/data /app/audio

# Copy audio and data files into "seed" directories for initialization
# IMPORTANT: This copy includes ALL subdirectories: athan/, coran/, system/
RUN mkdir -p /app/audio_seed /app/data_seed && \
    echo "📂 Copying audio files to seed directory..." && \
    cp -rv audio/* /app/audio_seed/ && \
    echo "📂 Audio files copied. Contents:" && \
    ls -lR /app/audio_seed/ && \
    echo "📂 Copying data files to seed directory..." && \
    cp -rv data/* /app/data_seed/ 2>/dev/null || true && \
    echo "✅ Seed directories created successfully"

# Make the entrypoint script executable
RUN chmod +x /app/entrypoint.sh

# Expose the ports
EXPOSE 7777 7778

# Use the entrypoint to initialize the volumes
ENTRYPOINT ["/app/entrypoint.sh"]

# Startup command
CMD ["node", "server.js"]
