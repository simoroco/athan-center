// ===== STATISTICS FUNCTIONALITY =====

let prayerStatsData = null;
let activityStatsData = null;
let prayerLast7DaysData = null;
let activityLast7DaysData = null;
let ramadanWeeks = new Set();
let prayerPieChartInstance = null;
let prayerBarChartInstance = null;
let activityPieChartInstance = null;
let activityBarChartInstance = null;
let fullscreenChartInstance = null;

// Open statistics modal
document.getElementById('statisticsBtn').addEventListener('click', async () => {
    document.getElementById('statisticsModal').style.display = 'block';
    await loadStatistics();
});

// Close statistics modal
document.getElementById('closeStatistics').addEventListener('click', () => {
    document.getElementById('statisticsModal').style.display = 'none';
});

// Close statistics modal on click outside (same mechanism as settingsModal)
window.addEventListener('click', (event) => {
    const modal = document.getElementById('statisticsModal');
    if (event.target === modal) {
        modal.style.display = 'none';
    }
});

// Close statistics modal on Escape key
document.addEventListener('keydown', (event) => {
    const modal = document.getElementById('statisticsModal');

    if (event.key === 'Escape' && modal && modal.style.display === 'block') {
        modal.style.display = 'none';
        event.preventDefault();
        event.stopPropagation();
    }
});

// Load all statistics data
async function loadStatistics() {
    try {
        // Fetch prayer statistics for last 7 days (pie chart)
        const prayer7DaysResponse = await fetch(`${API_BASE}/api/statistics/prayers/last-7-days`);
        const prayer7DaysData = await prayer7DaysResponse.json();
        prayerLast7DaysData = prayer7DaysData.statistics;

        // Fetch prayer statistics for 104 weeks (bar chart)
        const prayerResponse = await fetch(`${API_BASE}/api/statistics/prayers`);
        const prayerData = await prayerResponse.json();
        prayerStatsData = prayerData.statistics;

        // Fetch activity statistics for last 7 days (pie chart)
        const activity7DaysResponse = await fetch(`${API_BASE}/api/statistics/activities/last-7-days`);
        const activity7DaysData = await activity7DaysResponse.json();
        activityLast7DaysData = activity7DaysData.statistics;

        // Fetch activity statistics for 104 weeks (bar chart)
        const activityResponse = await fetch(`${API_BASE}/api/statistics/activities`);
        const activityData = await activityResponse.json();
        activityStatsData = activityData.statistics;

        // Fetch Ramadan weeks
        const ramadanResponse = await fetch(`${API_BASE}/api/hijri/ramadan-weeks`);
        const ramadanData = await ramadanResponse.json();

        // Create Ramadan weeks set
        ramadanWeeks = new Set();
        if (ramadanData.success && ramadanData.ramadan_dates) {
            ramadanData.ramadan_dates.forEach(rd => {
                const weekInfo = getWeekNumberFromDate(rd.gregorian_date);
                const weekStr = `${weekInfo.year}-W${String(weekInfo.week).padStart(2, '0')}`;
                ramadanWeeks.add(weekStr);
            });
        }

        // Render all charts
        renderPrayerPieChart();
        renderPrayerBarChart();
        renderActivityPieChart();
        renderActivityBarChart();
    } catch (error) {
        console.error('Error loading statistics:', error);
        alert('Error loading statistics: ' + error.message);
    }
}

// Helper function to get week number
function getWeekNumberFromDate(dateStr) {
    const d = new Date(dateStr);
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() + 4 - (d.getDay() || 7));
    const yearStart = new Date(d.getFullYear(), 0, 1);
    const weekNo = Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
    return { year: d.getFullYear(), week: weekNo };
}

// Render Prayer Pie Chart (Last 7 Days)
function renderPrayerPieChart() {
    const ctx = document.getElementById('prayerPieChart');

    if (!prayerLast7DaysData) {
        ctx.getContext('2d').fillText('No data available', 10, 50);
        return;
    }

    if (prayerPieChartInstance) {
        prayerPieChartInstance.destroy();
    }

    const isDarkMode = document.body.classList.contains('dark-mode');

    prayerPieChartInstance = new Chart(ctx, {
        type: 'pie',
        data: {
            labels: ['Not Done', 'On Time', 'Late'],
            datasets: [{
                data: [prayerLast7DaysData.not_done, prayerLast7DaysData.on_time, prayerLast7DaysData.late],
                backgroundColor: ['#6c757d', '#27ae60', '#ff8c00'],
                borderWidth: 2,
                borderColor: isDarkMode ? '#1a202c' : '#fff'
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50',
                        font: { size: 12 }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            const label = context.label || '';
                            const value = context.parsed || 0;
                            const total = prayerLast7DaysData.total;
                            const percentage = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
                            return `${label}: ${value} (${percentage}%)`;
                        }
                    }
                }
            }
        }
    });
}

// Render Prayer Bar Chart (104 weeks - all weeks displayed)
function renderPrayerBarChart() {
    const ctx = document.getElementById('prayerBarChart');

    if (!prayerStatsData || prayerStatsData.length === 0) {
        ctx.getContext('2d').fillText('No data available', 10, 50);
        return;
    }

    if (prayerBarChartInstance) {
        prayerBarChartInstance.destroy();
    }

    const isDarkMode = document.body.classList.contains('dark-mode');

    // Show last 52 weeks on desktop, 26 on tablet, 13 on mobile
    let weeksToShow = 52;
    if (window.innerWidth < 768) {
        weeksToShow = 13;
    } else if (window.innerWidth < 1200) {
        weeksToShow = 26;
    }

    // Filter out weeks with no data (total_prayers = 0)
    const dataWithPrayers = prayerStatsData.filter(s => s.total_prayers > 0);
    const recentData = dataWithPrayers.slice(-weeksToShow);

    const labels = recentData.map(s => {
        const isRamadan = ramadanWeeks.has(s.week);
        return isRamadan ? `🌙 ${s.week}` : s.week;
    });

    prayerBarChartInstance = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [
                {
                    label: 'Not Done',
                    data: recentData.map(s => s.not_done),
                    backgroundColor: '#6c757d',
                    stack: 'stack0'
                },
                {
                    label: 'Late',
                    data: recentData.map(s => s.late),
                    backgroundColor: '#ff8c00',
                    stack: 'stack0'
                },
                {
                    label: 'On Time',
                    data: recentData.map(s => s.on_time),
                    backgroundColor: '#27ae60',
                    stack: 'stack0'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            scales: {
                x: {
                    stacked: true,
                    ticks: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50',
                        maxRotation: 45,
                        minRotation: 45,
                        font: { size: 10 }
                    },
                    grid: {
                        color: isDarkMode ? '#4a5568' : '#e0e0e0'
                    }
                },
                y: {
                    stacked: true,
                    ticks: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50'
                    },
                    grid: {
                        color: isDarkMode ? '#4a5568' : '#e0e0e0'
                    }
                }
            },
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50',
                        font: { size: 12 }
                    }
                }
            }
        }
    });
}

// Render Activity Pie Chart (Last 7 Days)
function renderActivityPieChart() {
    const ctx = document.getElementById('activityPieChart');

    if (!activityLast7DaysData) {
        ctx.getContext('2d').fillText('No data available', 10, 50);
        return;
    }

    if (activityPieChartInstance) {
        activityPieChartInstance.destroy();
    }

    const isDarkMode = document.body.classList.contains('dark-mode');

    activityPieChartInstance = new Chart(ctx, {
        type: 'pie',
        data: {
            labels: ['Not Done', 'On Time', 'Late'],
            datasets: [{
                data: [activityLast7DaysData.not_done, activityLast7DaysData.on_time, activityLast7DaysData.late],
                backgroundColor: ['#6c757d', '#27ae60', '#ff8c00'],
                borderWidth: 2,
                borderColor: isDarkMode ? '#1a202c' : '#fff'
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50',
                        font: { size: 12 }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            const label = context.label || '';
                            const value = context.parsed || 0;
                            const total = activityLast7DaysData.total;
                            const percentage = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
                            return `${label}: ${value} (${percentage}%)`;
                        }
                    }
                }
            }
        }
    });
}

// Render Activity Bar Chart (all 104 weeks including empty weeks)
function renderActivityBarChart() {
    const ctx = document.getElementById('activityBarChart');

    if (!activityStatsData || activityStatsData.length === 0) {
        ctx.getContext('2d').fillText('No data available', 10, 50);
        return;
    }

    if (activityBarChartInstance) {
        activityBarChartInstance.destroy();
    }

    const isDarkMode = document.body.classList.contains('dark-mode');

    // Show last 52 weeks on desktop, 26 on tablet, 13 on mobile
    let weeksToShow = 52;
    if (window.innerWidth < 768) {
        weeksToShow = 13;
    } else if (window.innerWidth < 1200) {
        weeksToShow = 26;
    }

    const recentData = activityStatsData.slice(-weeksToShow);

    const labels = recentData.map(s => {
        const isRamadan = ramadanWeeks.has(s.week);
        return isRamadan ? `🌙 ${s.week}` : s.week;
    });

    activityBarChartInstance = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [
                {
                    label: 'Not Done',
                    data: recentData.map(s => s.not_done),
                    backgroundColor: '#6c757d',
                    stack: 'stack0'
                },
                {
                    label: 'Late',
                    data: recentData.map(s => s.late),
                    backgroundColor: '#ff8c00',
                    stack: 'stack0'
                },
                {
                    label: 'On Time',
                    data: recentData.map(s => s.on_time),
                    backgroundColor: '#27ae60',
                    stack: 'stack0'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            scales: {
                x: {
                    stacked: true,
                    ticks: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50',
                        maxRotation: 45,
                        minRotation: 45,
                        font: { size: 10 }
                    },
                    grid: {
                        color: isDarkMode ? '#4a5568' : '#e0e0e0'
                    }
                },
                y: {
                    stacked: true,
                    ticks: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50'
                    },
                    grid: {
                        color: isDarkMode ? '#4a5568' : '#e0e0e0'
                    }
                }
            },
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50',
                        font: { size: 12 }
                    }
                }
            }
        }
    });
}

// Expand prayer chart to fullscreen
document.getElementById('expandPrayerChart').addEventListener('click', () => {
    showFullscreenChart("Prayer Statistics - 2 Years' Histogram", prayerStatsData, 'prayer');
});

// Expand activity chart to fullscreen
document.getElementById('expandActivityChart').addEventListener('click', () => {
    showFullscreenChart('Daily Activities Statistics - 2 Years (104 weeks)', activityStatsData, 'activity');
});

// Show fullscreen chart
function showFullscreenChart(title, data, type) {
    const modal = document.getElementById('fullscreenChartModal');
    const titleElement = document.getElementById('fullscreenChartTitle');
    const canvas = document.getElementById('fullscreenChart');

    titleElement.textContent = title;
    modal.style.display = 'block';

    if (fullscreenChartInstance) {
        fullscreenChartInstance.destroy();
    }

    const isDarkMode = document.body.classList.contains('dark-mode');

    const labels = data.map(s => {
        const isRamadan = ramadanWeeks.has(s.week);
        return isRamadan ? `🌙 ${s.week}` : s.week;
    });

    fullscreenChartInstance = new Chart(canvas, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [
                {
                    label: 'Not Done',
                    data: data.map(s => s.not_done),
                    backgroundColor: '#6c757d',
                    stack: 'stack0'
                },
                {
                    label: 'Late',
                    data: data.map(s => s.late),
                    backgroundColor: '#ff8c00',
                    stack: 'stack0'
                },
                {
                    label: 'On Time',
                    data: data.map(s => s.on_time),
                    backgroundColor: '#27ae60',
                    stack: 'stack0'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                x: {
                    stacked: true,
                    ticks: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50',
                        maxRotation: 90,
                        minRotation: 45,
                        font: { size: 11 }
                    },
                    grid: {
                        color: isDarkMode ? '#4a5568' : '#e0e0e0'
                    }
                },
                y: {
                    stacked: true,
                    ticks: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50',
                        font: { size: 12 }
                    },
                    grid: {
                        color: isDarkMode ? '#4a5568' : '#e0e0e0'
                    }
                }
            },
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        color: isDarkMode ? '#e4e6eb' : '#2c3e50',
                        font: { size: 14 }
                    }
                }
            }
        }
    });
}

// Close fullscreen chart
document.getElementById('closeFullscreenChart').addEventListener('click', () => {
    document.getElementById('fullscreenChartModal').style.display = 'none';
    if (fullscreenChartInstance) {
        fullscreenChartInstance.destroy();
        fullscreenChartInstance = null;
    }
});

// Export to Excel
document.getElementById('exportExcelBtn').addEventListener('click', async () => {
    try {
        const response = await fetch(`${API_BASE}/api/statistics/export-excel`);
        const blob = await response.blob();

        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `athan-center-statistics-${Date.now()}.xlsx`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);

        alert('✅ Statistics exported successfully!');
    } catch (error) {
        console.error('Error exporting Excel:', error);
        alert('❌ Error exporting statistics: ' + error.message);
    }
});
