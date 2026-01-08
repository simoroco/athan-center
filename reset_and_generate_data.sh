#!/bin/bash

echo "🗑️  Suppression des données historiques..."

# Reset prayer checks and daily activities
curl -X POST http://localhost:7777/api/prayer-checks/reset
echo ""

echo "✅ Données historiques supprimées"
echo ""
echo "📝 Génération de nouvelles données via script Node.js..."

# Execute the generation script inside the container
docker exec athan-center sh -c "cd /app && node -e \"
const Database = require('better-sqlite3');
const db = new Database('./data/prayer.db');

console.log('🗑️  Suppression des prières...');
db.prepare('DELETE FROM prayers').run();
console.log('✅ Prières supprimées');

console.log('\\n📝 Génération de nouvelles données...');

const prayerNames = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];
const prayerTimes = {
    'Fajr | Sobh': '07:13',
    'Dohr': '12:57',
    'Asr': '14:52',
    'Maghrib': '17:11',
    'Isha': '19:18'
};

const today = new Date();
const startDate = new Date(today);
startDate.setDate(startDate.getDate() - (104 * 7));

const insertPrayer = db.prepare('INSERT INTO prayers (date, prayer_name, prayer_time) VALUES (?, ?, ?)');
const insertCheck = db.prepare('INSERT INTO prayer_checks (date, prayer_name, checked) VALUES (?, ?, ?)');

let totalDays = 0;
let totalPrayers = 0;

const currentDate = new Date(startDate);
while (currentDate <= today) {
    const dateStr = currentDate.toISOString().split('T')[0];
    
    prayerNames.forEach(prayerName => {
        insertPrayer.run(dateStr, prayerName, prayerTimes[prayerName]);
        
        const random = Math.random();
        let checked = 0;
        if (random < 0.7) {
            checked = 1;
        } else if (random < 0.9) {
            checked = 2;
        }
        
        insertCheck.run(dateStr, prayerName, checked);
        totalPrayers++;
    });
    
    totalDays++;
    currentDate.setDate(currentDate.getDate() + 1);
}

console.log(\\\`✅ \\\${totalPrayers} prières générées pour \\\${totalDays} jours\\\`);
console.log(\\\`✅ Cela représente \\\${Math.floor(totalDays / 7)} semaines complètes\\\`);

const daysWithLessThan5 = db.prepare(\\\`
    SELECT date, COUNT(*) as count
    FROM prayers
    WHERE prayer_name IN ('Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha')
    GROUP BY date
    HAVING count != 5
\\\`).all();

if (daysWithLessThan5.length > 0) {
    console.log(\\\`\\\\n⚠️  Attention: \\\${daysWithLessThan5.length} jours n'ont pas exactement 5 prières\\\`);
} else {
    console.log('\\\\n✅ Tous les jours ont exactement 5 prières!');
}

db.close();
console.log('\\\\n✅ Génération terminée!');
\""

echo ""
echo "🔄 Redémarrage du conteneur..."
docker-compose restart athan-center

echo ""
echo "✅ Terminé! Vérification des statistiques..."
sleep 3

# Check statistics
curl -s http://localhost:7777/api/statistics/prayers | jq '.statistics | map(select(.total_prayers > 0)) | sort_by(.total_prayers) | reverse | .[0] | {week, total_prayers, on_time, late, not_done}'
