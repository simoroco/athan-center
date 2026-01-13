# 🔧 Correction du bug du volume Fajr

## 🐛 Problème identifié

La prière **Fajr | Sobh** utilisait toujours le volume général (`volumeSlider`) au lieu du volume spécifique Fajr (`fajrVolumeSlider`) lors de la lecture audio sur le serveur.

### Cause du bug

La logique de `sync_fajr_volume` était **inversée** entre l'interface web et le serveur :

**Avant la correction** :
- Interface web : `sync_fajr_volume = '1'` → Checkbox cochée → Volume indépendant
- Serveur : `sync_fajr_volume = '1'` → Utilise `fajr_volume` (volume spécifique)
- **MAIS** : Valeur par défaut = `'0'` → Le serveur utilisait le volume général par défaut !

**Résultat** : Par défaut, Fajr utilisait toujours le volume général au lieu de son volume spécifique.

## ✅ Corrections apportées

### 1. **Serveur** (`server.js` lignes 610-632)

**Nouvelle logique** :
```javascript
// sync_fajr_volume: '0' = independent (use fajr_volume), '1' = synced (use volume)
const isSynced = syncFajrVolumeRow ? syncFajrVolumeRow.value === '1' : false;

if (isSynced) {
    // Use main volume (synced)
    volumePercent = volumeRow ? parseInt(volumeRow.value) : 50;
    log(`[playAthan] Using synced main volume for Fajr: ${volumePercent}%`);
} else {
    // Use specific Fajr volume (independent)
    volumePercent = fajrVolumeRow ? parseInt(fajrVolumeRow.value) : 50;
    log(`[playAthan] Using independent Fajr volume: ${volumePercent}%`);
}
```

### 2. **Interface web** (`app.js`)

**Modifications** :
- Ligne 1362 : Commentaire mis à jour → "checked = synced with main, unchecked = independent volume"
- Ligne 1365 : `const isSynced = e.target.checked;` (au lieu de `useIndependentVolume`)
- Ligne 1370 : `value: isSynced ? '1' : '0'` (logique inversée)
- Ligne 1377 : `setFajrVolumeSliderEnabled(isServerEnabled && !isSynced);` (slider actif si NOT synced)
- Ligne 1380 : `if (isSynced && ...)` (synchroniser si checkbox cochée)
- Ligne 2664 : Commentaire mis à jour
- Ligne 2668-2669 : `const isSynced = settings.sync_fajr_volume === '1';`
- Ligne 2682 : `setFajrVolumeSliderEnabled(isServerEnabled && !isSynced);`
- Ligne 1269 : `if (syncFajrVolumeCheckbox && syncFajrVolumeCheckbox.checked)` (sync si coché)

### 3. **Interface HTML** (`index.html` lignes 286-296)

**Nouveau label** :
```html
<span>Sync Fajr | Sobh volume with main volume</span>
```

**Nouveau texte d'aide** :
```
When enabled, Fajr | Sobh uses the same volume as other prayers. 
When disabled, you can set a specific volume below.
```

## 🎯 Comportement après correction

### Valeur par défaut (`sync_fajr_volume = '0'`)
- ✅ Checkbox **décochée** par défaut
- ✅ Volume Fajr **indépendant** (utilise `fajr_volume`)
- ✅ Slider Fajr **actif** et modifiable
- ✅ Fajr joue à 50% (valeur par défaut de `fajr_volume`)

### Checkbox décochée (`sync_fajr_volume = '0'`)
- ✅ Volume Fajr **indépendant**
- ✅ Slider Fajr **actif**
- ✅ Fajr utilise `fajr_volume` (ex: 30%)
- ✅ Autres prières utilisent `volume` (ex: 50%)

### Checkbox cochée (`sync_fajr_volume = '1'`)
- ✅ Volume Fajr **synchronisé** avec le volume général
- ✅ Slider Fajr **désactivé** (grisé)
- ✅ Fajr utilise `volume` (ex: 50%)
- ✅ Changer le volume général met à jour automatiquement le slider Fajr

## 🧪 Tests à effectuer

### Test 1 : Volume indépendant (par défaut)
1. Ouvrir Settings
2. Vérifier que la checkbox "Sync Fajr | Sobh volume with main volume" est **décochée**
3. Vérifier que le slider "Fajr | Sobh prayer volume" est **actif** (pas grisé)
4. Mettre le volume général à **50%**
5. Mettre le volume Fajr à **30%**
6. Tester l'athan Fajr (bouton "Test Audio" ou attendre l'heure de Fajr)
7. **Résultat attendu** : L'audio joue à **30%** (volume Fajr)
8. Vérifier les logs : `[playAthan] Using independent Fajr volume: 30%`

### Test 2 : Volume synchronisé
1. Ouvrir Settings
2. **Cocher** la checkbox "Sync Fajr | Sobh volume with main volume"
3. Vérifier que le slider Fajr est **désactivé** (grisé)
4. Vérifier que le slider Fajr affiche la même valeur que le volume général
5. Mettre le volume général à **70%**
6. Vérifier que le slider Fajr passe automatiquement à **70%**
7. Tester l'athan Fajr
8. **Résultat attendu** : L'audio joue à **70%** (volume général)
9. Vérifier les logs : `[playAthan] Using synced main volume for Fajr: 70%`

### Test 3 : Changement de mode
1. Mettre le volume général à **50%**
2. Mettre le volume Fajr à **30%** (checkbox décochée)
3. **Cocher** la checkbox de synchronisation
4. Vérifier que le slider Fajr passe à **50%** (synchronisé)
5. **Décocher** la checkbox
6. Vérifier que le slider Fajr reste à **50%** (valeur sauvegardée)
7. Modifier le slider Fajr à **25%**
8. Tester l'athan Fajr
9. **Résultat attendu** : L'audio joue à **25%**

### Test 4 : Autres prières (non affectées)
1. Mettre le volume général à **60%**
2. Mettre le volume Fajr à **20%** (checkbox décochée)
3. Tester l'athan pour **Dohr** (ou autre prière)
4. **Résultat attendu** : L'audio joue à **60%** (volume général)
5. Vérifier les logs : Pas de mention de "Fajr volume"

## 📝 Logs de débogage

Les logs du serveur affichent maintenant clairement quel volume est utilisé :

```
[playAthan] Using independent Fajr volume: 30%
```
ou
```
[playAthan] Using synced main volume for Fajr: 50%
```

## 🔄 Migration des données existantes

**Aucune migration nécessaire** : La valeur par défaut `sync_fajr_volume = '0'` est déjà correcte dans la base de données.

Les utilisateurs existants qui avaient :
- Checkbox décochée → Comportement inchangé (volume indépendant)
- Checkbox cochée → **Comportement inversé** (maintenant synchronisé au lieu d'indépendant)

**Note** : Si des utilisateurs avaient coché la checkbox pour avoir un volume indépendant, ils devront la **décocher** après la mise à jour.

## 🎯 Résumé des changements

| Fichier | Lignes modifiées | Description |
|---------|------------------|-------------|
| `server.js` | 610-632 | Inversion de la logique `sync_fajr_volume` |
| `app.js` | 1267-1269, 1362-1390, 2664-2683 | Mise à jour de l'interface pour correspondre au serveur |
| `index.html` | 286-296 | Correction du label et du texte d'aide |

## ✅ Validation

- ✅ Logique serveur corrigée
- ✅ Logique interface web corrigée
- ✅ Labels HTML mis à jour
- ✅ Commentaires dans le code clarifiés
- ✅ Comportement par défaut cohérent
- ✅ Documentation créée

## 🚀 Déploiement

1. Rebuilder l'image Docker (si nécessaire)
2. Redémarrer le conteneur
3. Tester les 4 scénarios ci-dessus
4. Vérifier les logs pour confirmer le bon volume utilisé
