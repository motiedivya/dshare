document.addEventListener('DOMContentLoaded', () => {
    // === Flashlight Effect ===
    const root = document.documentElement;
    document.addEventListener('mousemove', (e) => {
        root.style.setProperty('--cursor-x', e.clientX + 'px');
        root.style.setProperty('--cursor-y', e.clientY + 'px');
    });

    // === Typewriter Intro ===
    const titleElement = document.querySelector('h1');
    if (titleElement) {
        const originalText = titleElement.innerText;
        titleElement.innerText = '';
        titleElement.classList.add('blinking-cursor');

        let i = 0;
        const typeWriter = () => {
            if (i < originalText.length) {
                titleElement.innerText += originalText.charAt(i);
                i++;
                setTimeout(typeWriter, 100 + Math.random() * 150); // Random typing speed
            } else {
                // Stop blinking cursor after a while? Na, keep it.
            }
        };
        setTimeout(typeWriter, 500); // Start delay
    }

    // === Random "Secrets" ===
    const secrets = [
        "THEY ARE WATCHING",
        "ENCRYPTING CONNECTION...",
        "UNAUTHORIZED ACCESS DETECTED",
        "GHOST PROTOCOL INITIATED",
        "DON'T LOOK BEHIND YOU"
    ];

    const secretContainer = document.createElement('div');
    secretContainer.style.position = 'fixed';
    secretContainer.style.bottom = '10px';
    secretContainer.style.right = '10px';
    secretContainer.style.fontSize = '0.7em';
    secretContainer.style.color = '#f00';
    secretContainer.style.opacity = '0';
    secretContainer.style.transition = 'opacity 1s';
    document.body.appendChild(secretContainer);

    setInterval(() => {
        if (Math.random() > 0.7) {
            const secret = secrets[Math.floor(Math.random() * secrets.length)];
            secretContainer.innerText = `>> SYSTEM ALERT: ${secret}`;
            secretContainer.style.opacity = '1';
            setTimeout(() => {
                secretContainer.style.opacity = '0';
            }, 3000);
        }
    }, 5000);
});
