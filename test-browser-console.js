/**
 * Browser Console Test Script for Athan Center Import
 * 
 * HOW TO USE:
 * 1. Open http://localhost:7777 in your browser
 * 2. Open DevTools (F12) → Console tab
 * 3. Copy and paste this entire script
 * 4. Press Enter
 * 
 * The script will:
 * - Navigate to 2026-01-08
 * - Check that Daily Activities show correct checkmarks
 * - Report PASS/FAIL
 */

(async function runBrowserTest() {
    console.log('%c=== ATHAN CENTER IMPORT BROWSER TEST ===', 'font-size:16px;font-weight:bold;color:#2196F3');
    
    // Step 1: Navigate to 2026-01-08
    console.log('Step 1: Navigating to 2026-01-08...');
    
    // Simulate clicking the calendar icon and selecting 2026-01-08
    const calendarBtn = document.querySelector('.calendar-icon');
    if (calendarBtn) calendarBtn.click();
    
    await new Promise(r => setTimeout(r, 500));
    
    // Find and click the day element for 2026-01-08
    const dayElements = document.querySelectorAll('.calendar-day');
    let targetDay = null;
    dayElements.forEach(el => {
        if (el.dataset.date === '2026-01-08') {
            targetDay = el;
        }
    });
    
    if (!targetDay) {
        // If calendar modal is not open, try another approach
        console.log('Calendar day not found in modal, setting date manually...');
        if (typeof currentDate !== 'undefined') {
            currentDate = new Date('2026-01-08T12:00:00');
            if (typeof loadPrayers === 'function') await loadPrayers();
        }
    } else {
        targetDay.click();
        await new Promise(r => setTimeout(r, 1000));
    }
    
    // Step 2: Verify Daily Activities section
    console.log('Step 2: Checking Daily Activities for 2026-01-08...');
    await new Promise(r => setTimeout(r, 1000));
    
    const activitiesContent = document.getElementById('dailyActivitiesContent');
    if (!activitiesContent) {
        console.error('%c❌ FAIL: dailyActivitiesContent not found', 'color:red;font-weight:bold');
        return;
    }
    
    const activityItems = activitiesContent.querySelectorAll('.activity-item');
    const results = {};
    
    activityItems.forEach(item => {
        const name = item.getAttribute('data-activity');
        const hasGreenCheck = item.querySelector('.prayer-check-mark') !== null;
        const hasOrangeCheck = item.querySelector('.prayer-redcheck-mark') !== null;
        results[name] = { green: hasGreenCheck, orange: hasOrangeCheck };
    });
    
    console.log('Activity checks found:', results);
    
    // Step 3: Validate expected state
    // Expected: Coran=green(1), Tasbih=orange(2), Nawafil=green(1)
    const expected = {
        'Coran': { type: 'green', expectedChecked: 1 },
        'Tasbih': { type: 'orange', expectedChecked: 2 },
        'Nawafil': { type: 'green', expectedChecked: 1 }
    };
    
    let allPassed = true;
    
    for (const [name, exp] of Object.entries(expected)) {
        const res = results[name];
        if (!res) {
            console.error(`%c❌ FAIL: ${name} not found in Daily Activities`, 'color:red');
            allPassed = false;
            continue;
        }
        
        const isCorrect = exp.type === 'green' ? res.green : res.orange;
        if (isCorrect) {
            console.log(`%c✅ PASS: ${name} has correct ${exp.type} checkmark`, 'color:green');
        } else {
            console.error(`%c❌ FAIL: ${name} expected ${exp.type} checkmark but got: green=${res.green}, orange=${res.orange}`, 'color:red');
            allPassed = false;
        }
    }
    
    // Step 4: Check that NO legacy names appear
    const allActivityNames = Array.from(activityItems).map(el => el.getAttribute('data-activity'));
    const legacyNames = ['Read Coran', 'Tasbih & Dikr'];
    const foundLegacy = legacyNames.filter(n => allActivityNames.includes(n));
    
    if (foundLegacy.length > 0) {
        console.error('%c❌ FAIL: Legacy activity names still visible:', 'color:red', foundLegacy);
        allPassed = false;
    } else {
        console.log('%c✅ PASS: No legacy activity names visible in UI', 'color:green');
    }
    
    // Final result
    if (allPassed) {
        console.log('%c\n🎉 ALL TESTS PASSED!', 'font-size:18px;font-weight:bold;color:green');
    } else {
        console.log('%c\n⚠️ SOME TESTS FAILED', 'font-size:18px;font-weight:bold;color:red');
    }
})();
