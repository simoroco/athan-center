const Database = require('better-sqlite3');
const path = require('path');

// Connect to the database
const dbPath = path.join(__dirname, 'app', 'data', 'prayer.db');
const db = new Database(dbPath);

console.log('🗑️  Suppression des données historiques...');

// Delete all prayers
db.prepare('DELETE FROM prayers').run();
console.log('✅ Toutes les prières supprimées');

// Delete all prayer checks
db.prepare('DELETE FROM prayer_checks').run();
console.log('✅ Tous les checks de prières supprimés');

// Delete all daily activities
db.prepare('DELETE FROM daily_activities').run();
console.log('✅ Toutes les activités quotidiennes supprimées');

console.log('\n📝 Génération de nouvelles données...');

// Generate prayer times for the last 104 weeks (2 years)
const today = new Date();
const startDate = new Date(today);
startDate.setDate(startDate.getDate() - (104 * 7)); // 104 weeks ago

const prayerNames = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];
const prayerTimes = {
    'Fajr | Sobh': '07:13',
    'Dohr': '12:57',
    'Asr': '14:52',
    'Maghrib': '17:11',
    'Isha': '19:18'
};

const insertPrayer = db.prepare('INSERT INTO prayers (date, prayer_name, prayer_time) VALUES (?, ?, ?)');
const insertCheck = db.prepare('INSERT INTO prayer_checks (date, prayer_name, checked) VALUES (?, ?, ?)');

let totalDays = 0;
let totalPrayers = 0;

// Generate data for each day
const currentDate = new Date(startDate);
while (currentDate <= today) {
    const dateStr = currentDate.toISOString().split('T')[0];
    
    // Insert all 5 prayers for this day
    prayerNames.forEach(prayerName => {
        insertPrayer.run(dateStr, prayerName, prayerTimes[prayerName]);
        
        // Randomly mark prayers as checked (on_time=1, late=2, not_done=0)
        const random = Math.random();
        let checked = 0;
        if (random < 0.7) {
            checked = 1; // 70% on time
        } else if (random < 0.9) {
            checked = 2; // 20% late
        }
        // 10% not done (checked = 0)
        
        insertCheck.run(dateStr, prayerName, checked);
        totalPrayers++;
    });
    
    totalDays++;
    currentDate.setDate(currentDate.getDate() + 1);
}

console.log(`✅ ${totalPrayers} prières générées pour ${totalDays} jours`);
console.log(`✅ Cela représente ${Math.floor(totalDays / 7)} semaines complètes`);

// Verify the data
const weekCount = db.prepare(`
    SELECT COUNT(DISTINCT date) as days
    FROM prayers
    WHERE prayer_name IN ('Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha')
`).get();

const prayerCount = db.prepare(`
    SELECT COUNT(*) as count
    FROM prayers
    WHERE prayer_name IN ('Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha')
`).get();

console.log(`\n📊 Vérification:`);
console.log(`   - Jours avec prières: ${weekCount.days}`);
console.log(`   - Total de prières: ${prayerCount.count}`);
console.log(`   - Moyenne par jour: ${(prayerCount.count / weekCount.days).toFixed(2)}`);

// Check if all days have exactly 5 prayers
const daysWithLessThan5 = db.prepare(`
    SELECT date, COUNT(*) as count
    FROM prayers
    WHERE prayer_name IN ('Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha')
    GROUP BY date
    HAVING count != 5
`).all();

if (daysWithLessThan5.length > 0) {
    console.log(`\n⚠️  Attention: ${daysWithLessThan5.length} jours n'ont pas exactement 5 prières:`);
    daysWithLessThan5.forEach(day => {
        console.log(`   - ${day.date}: ${day.count} prières`);
    });
} else {
    console.log(`\n✅ Tous les jours ont exactement 5 prières!`);
}

db.close();
console.log('\n✅ Génération terminée!');
