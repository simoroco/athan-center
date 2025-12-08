# 💾 Dossier Data

Ce dossier contient la base de données SQLite de Athan Center.

## 📁 Contenu

- `prayer.db` - Base de données SQLite (créée automatiquement)

## 🗄️ Structure de la Base de Données

### Table `prayers`
Stocke les horaires de prière pour chaque jour.

| Colonne | Type | Description |
|---------|------|-------------|
| id | INTEGER | Identifiant auto-incrémenté |
| date | TEXT | Date au format YYYY-MM-DD |
| prayer_name | TEXT | Nom de la prière (Fajr, Dhuhr, etc.) |
| prayer_time | TEXT | Heure au format HH:MM |

**Index** : UNIQUE(date, prayer_name)

### Table `settings`
Paramètres globaux de l'application.

| Colonne | Type | Description |
|---------|------|-------------|
| key | TEXT | Clé du paramètre (PRIMARY KEY) |
| value | TEXT | Valeur du paramètre |

**Paramètres par défaut** :
- `ics_url` : URL du calendrier ICS
- `location_type` : Type de localisation (url, gps, city, wifi)
- `audio_file` : Nom du fichier audio d'athan

### Table `prayer_settings`
Configuration d'activation pour chaque prière.

| Colonne | Type | Description |
|---------|------|-------------|
| prayer_name | TEXT | Nom de la prière (PRIMARY KEY) |
| enabled | INTEGER | 1 = activé, 0 = désactivé |

### Table `skip_next`
Gestion de l'annulation ponctuelle du prochain athan.

| Colonne | Type | Description |
|---------|------|-------------|
| id | INTEGER | Toujours 1 (PRIMARY KEY) |
| skip | INTEGER | 1 = skip actif, 0 = normal |

## 🔍 Accès à la Base de Données

### Depuis le conteneur Docker

```bash
# Entrer dans le conteneur
docker exec -it athan-center /bin/bash

# Ouvrir la base de données
sqlite3 /app/data/prayer.db

# Exemples de requêtes
sqlite> .tables                          # Lister les tables
sqlite> SELECT * FROM prayers LIMIT 5;   # Voir quelques prières
sqlite> SELECT * FROM settings;          # Voir les paramètres
sqlite> .exit                            # Quitter
```

### Depuis l'hôte (si SQLite est installé)

```bash
sqlite3 data/prayer.db
```

## 📊 Requêtes Utiles

### Voir les prières d'aujourd'hui

```sql
SELECT * FROM prayers 
WHERE date = date('now', 'localtime') 
ORDER BY prayer_time;
```

### Compter le nombre de prières stockées

```sql
SELECT COUNT(*) FROM prayers;
```

### Voir les prières d'une date spécifique

```sql
SELECT * FROM prayers 
WHERE date = '2024-11-10' 
ORDER BY prayer_time;
```

### Voir quelles prières sont activées

```sql
SELECT prayer_name, 
       CASE WHEN enabled = 1 THEN 'Activé' ELSE 'Désactivé' END as statut
FROM prayer_settings;
```

### Voir tous les paramètres

```sql
SELECT * FROM settings;
```

### Nettoyer les anciennes prières (> 6 mois)

```sql
DELETE FROM prayers 
WHERE date < date('now', '-6 months');

VACUUM;  -- Optimiser la base de données
```

## 💾 Backup et Restauration

### Créer un backup

```bash
# Backup simple
cp data/prayer.db data/prayer.db.backup

# Backup avec date
cp data/prayer.db data/prayer.db.$(date +%Y%m%d)

# Backup compressé
tar -czf backup-prayer-$(date +%Y%m%d).tar.gz data/prayer.db
```

### Restaurer un backup

```bash
# Arrêter l'application
docker-compose down

# Restaurer
cp data/prayer.db.backup data/prayer.db

# Redémarrer
docker-compose up -d
```

### Export en CSV

```bash
sqlite3 data/prayer.db <<EOF
.headers on
.mode csv
.output prayers_export.csv
SELECT * FROM prayers;
.quit
EOF
```

### Import depuis CSV

```bash
sqlite3 data/prayer.db <<EOF
.mode csv
.import prayers_import.csv prayers
.quit
EOF
```

## 🔧 Maintenance

### Optimiser la base de données

```sql
-- Reconstruire les index
REINDEX;

-- Optimiser l'espace
VACUUM;

-- Analyser pour les statistiques
ANALYZE;
```

### Vérifier l'intégrité

```sql
PRAGMA integrity_check;
```

### Voir la taille de la base

```bash
ls -lh data/prayer.db
```

### Statistiques

```sql
-- Nombre de prières par mois
SELECT strftime('%Y-%m', date) as month, COUNT(*) as count
FROM prayers
GROUP BY month
ORDER BY month DESC;

-- Nombre de prières par nom
SELECT prayer_name, COUNT(*) as count
FROM prayers
GROUP BY prayer_name;
```

## ⚠️ Avertissements

### Ne pas modifier manuellement

La base de données est gérée automatiquement par l'application. Des modifications manuelles peuvent causer des problèmes.

### Sauvegarde régulière

Sauvegardez régulièrement la base de données, surtout :
- Avant une mise à jour
- Avant de modifier les paramètres
- Une fois par mois minimum

### Permissions

Assurez-vous que le conteneur Docker a les bonnes permissions :

```bash
sudo chown -R 1000:1000 data/
chmod 644 data/prayer.db
```

## 🔄 Migration

Si vous migrez vers un nouveau serveur :

1. **Sauvegarder** :
```bash
cp data/prayer.db /path/to/backup/
```

2. **Transférer** :
```bash
scp data/prayer.db user@new-server:/path/to/athan-center/data/
```

3. **Vérifier** :
```bash
# Sur le nouveau serveur
sqlite3 data/prayer.db "SELECT COUNT(*) FROM prayers;"
```

## 📈 Monitoring

### Taille de la base de données

```bash
# Surveiller la croissance
watch -n 60 'ls -lh data/prayer.db'
```

### Dernière modification

```bash
stat data/prayer.db
```

## 🐛 Dépannage

### La base de données est corrompue

```bash
# 1. Arrêter l'application
docker-compose down

# 2. Vérifier l'intégrité
sqlite3 data/prayer.db "PRAGMA integrity_check;"

# 3. Si corrompu, restaurer depuis backup
cp data/prayer.db.backup data/prayer.db

# 4. Redémarrer
docker-compose up -d
```

### Erreur "database is locked"

```bash
# Vérifier les processus utilisant la DB
lsof data/prayer.db

# Redémarrer l'application
docker-compose restart
```

### La base de données est vide

```bash
# Forcer une mise à jour des horaires
# Via l'interface web : Paramètres > Mettre à jour les horaires maintenant

# Ou via API
curl -X POST http://localhost:7777/api/update-prayers
```

## 📚 Ressources

- [SQLite Documentation](https://www.sqlite.org/docs.html)
- [SQL Tutorial](https://www.w3schools.com/sql/)
- [SQLite Browser](https://sqlitebrowser.org/) - Interface graphique pour SQLite

---

**Note** : Ce fichier est créé automatiquement au premier démarrage de l'application.
