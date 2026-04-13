// Portfolio Configuration
const APPS = {
    filelister: {
        name: "FileLister Pro",
        tagline: "The ultimate guardian of your storage.",
        icon: "📁",
        salt: "FileLister-Secret-Salt-2026-Porto",
        features: [
            "SHA-256 Cryptographic Hashing",
            "Final Binary Verification (Byte-by-Byte)",
            "Detailed Progress Monitoring",
            "macOS Trash Integration",
            "Safety Lock: Prevents total deletion"
        ]
    },
    knockapp: {
        name: "KnockApp",
        tagline: "Sound triggers powered by physics.",
        icon: "🔊",
        salt: "KnockApp-Secret-Salt-2026-Standard",
        features: [
            "Accelerometer Impact Detection",
            "Custom Sound Library Support",
            "Sensitivity Calibration",
            "Low Latency Audio Engine"
        ]
    },
    brightness: {
        name: "BrightnessApp",
        tagline: "Control your displays with precision.",
        icon: "☀️",
        salt: "Brightness-Secret-Salt-999-Lux",
        features: [
            "Native DDC/CI Support",
            "Keyboard Shortcuts Integration",
            "Dual-Monitor Synchronization",
            "Zero Energy Footprint"
        ]
    },
    systempulse: {
        name: "System Pulse",
        tagline: "Real-time health monitor and optimizer.",
        icon: "⚡",
        salt: "Pulse-Secret-Salt-Alpha-Centauri",
        features: [
            "Memory Purge Technology",
            "Background Task Sentinel",
            "Visual CPU & Network Charts",
            "Smart Battery Advisor"
        ]
    }
};

// --- App Selection & UI Logic ---

function selectApp(appId) {
    const app = APPS[appId];
    if (!app) return;

    document.getElementById('detailIcon').innerText = app.icon;
    document.getElementById('detailTitle').innerText = app.name;
    document.getElementById('detailTagline').innerText = app.tagline;
    
    // Update features list
    const featuresList = document.getElementById('detailFeatures');
    featuresList.innerHTML = "";
    app.features.forEach(f => {
        const li = document.createElement('li');
        li.innerText = f;
        featuresList.appendChild(li);
    });

    document.getElementById('details').classList.remove('hidden');
    
    // Auto-select in the generator dropdown for convenience
    document.getElementById('appSelect').value = appId;
}

function hideDetails() {
    document.getElementById('details').classList.add('hidden');
}

// --- Payment & Activation Logic ---

function simulatePayment(provider) {
    const btn = event.currentTarget;
    const originalText = btn.innerHTML;
    
    btn.innerHTML = `<span>⏳ Verifying ${provider}...</span>`;
    btn.style.opacity = "0.7";
    btn.style.pointerEvents = "none";

    // Simulate payment processing delay
    setTimeout(() => {
        document.getElementById('generatorContainer').classList.add('unlocked');
        btn.innerHTML = `<span>✅ Support Confirmed!</span>`;
        btn.style.background = "#34C759";
        btn.style.color = "white";
        
        // Scroll to the unlocked generator
        document.getElementById('generatorContainer').scrollIntoView({ behavior: 'smooth', block: 'center' });
    }, 2000);
}

// --- License Generation Logic ---

const SALT_MAP = {
    filelister: "FileLister-Secret-Salt-2026-Porto",
    knockapp: "KnockApp-Secret-Salt-2026-Standard",
    brightness: "Brightness-Secret-Salt-999-Lux",
    systempulse: "Pulse-Secret-Salt-Alpha-Centauri"
};

document.getElementById('generateBtn').addEventListener('click', async () => {
    const name = document.getElementById('custName').value.trim();
    const email = document.getElementById('custEmail').value.trim();
    const appId = document.getElementById('appSelect').value;

    if (!name || !email) {
        alert("Please provide your name and e-mail for registration.");
        return;
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
        alert("Please enter a valid e-mail address.");
        return;
    }

    // Generator Logic
    const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let seed = "";
    for (let i = 0; i < 20; i++) {
        seed += letters.charAt(Math.floor(Math.random() * letters.length));
    }

    const salt = SALT_MAP[appId];
    const signature = await calculateSignature(seed, salt);

    let formattedKey = "";
    for (let i = 0; i < 5; i++) {
        formattedKey += seed.substring(i * 4, i * 4 + 4) + "-";
    }
    formattedKey += signature;

    // Display Result
    document.getElementById('finalKey').innerText = formattedKey;
    document.getElementById('resultBox').classList.remove('hidden');
    document.getElementById('mailBtn').classList.remove('hidden');
});

async function calculateSignature(seed, salt) {
    const input = seed + salt;
    const msgBuffer = new TextEncoder().encode(input);
    const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
    return hashHex.substring(0, 4);
}

// Helper: Copy Key
function copyKey() {
    const key = document.getElementById('finalKey').innerText;
    navigator.clipboard.writeText(key).then(() => {
        const btn = document.querySelector('.copy-small');
        btn.innerText = "✓";
        setTimeout(() => btn.innerText = "📋", 2000);
    });
}

// Helper: Open Email
document.getElementById('mailBtn').addEventListener('click', () => {
    const name = document.getElementById('custName').value.trim();
    const email = document.getElementById('custEmail').value.trim();
    const key = document.getElementById('finalKey').innerText;
    const appName = APPS[document.getElementById('appSelect').value].name;

    const subject = encodeURIComponent(`Your ${appName} Lifetime License`);
    const body = encodeURIComponent(`Hello ${name},\n\nThank you for supporting our development!\n\nYour Pro License Key for ${appName} is: ${key}\n\nTo activate, open the app and go to the license menu.\n\nEnjoy your premium software!\n- LS Developer Suite Team`);
    
    window.location.href = `mailto:${email}?subject=${subject}&body=${body}`;
});

// --- Contact Form Logic ---

document.getElementById('openContactBtn').addEventListener('click', () => {
    document.getElementById('contactModal').classList.remove('hidden');
});

document.getElementById('closeContactBtn').addEventListener('click', () => {
    document.getElementById('contactModal').classList.add('hidden');
});

document.getElementById('sendContactBtn').addEventListener('click', () => {
    const name = document.getElementById('contactName').value.trim();
    const email = document.getElementById('contactEmail').value.trim();
    const message = document.getElementById('contactMessage').value.trim();

    if (!name || !email || !message) {
        alert("Por favor, preenche todos os campos para enviar a mensagem.");
        return;
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
        alert("Por favor, introduz um e-mail válido.");
        return;
    }

    const subject = encodeURIComponent(`Contacto Single Use Apps: Mensagem de ${name}`);
    const body = encodeURIComponent(`Nome: ${name}\nE-mail de contacto: ${email}\n\n--- Mensagem ---\n\n${message}`);
    
    window.location.href = `mailto:luisdanielsilva@gmail.com?subject=${subject}&body=${body}`;
    
    // Close modal and clear form
    document.getElementById('contactModal').classList.add('hidden');
    document.getElementById('contactName').value = '';
    document.getElementById('contactEmail').value = '';
    document.getElementById('contactMessage').value = '';
});
