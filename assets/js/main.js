/* Luma landing — entrance animations + soft parallax.
   Plain ES2022, no dependencies. Respects prefers-reduced-motion. */

(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* --- 1. Entrance reveal: stagger children of each [data-section] --- */
  const reveal = (el, delay = 0) => {
    setTimeout(() => el.classList.add('is-in'), delay);
  };

  if (reduce) {
    // Reveal everything immediately, no transitions
    document.querySelectorAll('[data-animate]').forEach(el => el.classList.add('is-in'));
  } else {
    // Hero animates on load
    document.querySelectorAll('.hero [data-animate]').forEach((el, i) => reveal(el, i * 100));

    // Sections animate when 20% visible — children staggered
    const io = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        const targets = entry.target.querySelectorAll('[data-animate]');
        targets.forEach((el, i) => reveal(el, i * 80));
        io.unobserve(entry.target);
      });
    }, { threshold: 0.2, rootMargin: '0px 0px -10% 0px' });

    document.querySelectorAll('[data-section]').forEach(s => io.observe(s));
  }

  /* --- 2. Soft parallax on phone strip (only if motion allowed) --- */
  if (!reduce) {
    const phones = document.querySelectorAll('.phones-rail img[data-parallax]');
    if (phones.length) {
      let ticking = false;
      const update = () => {
        const phonesSection = document.querySelector('.phones');
        if (!phonesSection) return;
        const rect = phonesSection.getBoundingClientRect();
        const vh = window.innerHeight;
        // -1 .. +1 as section passes through viewport
        const t = (rect.top + rect.height / 2 - vh / 2) / vh;
        phones.forEach(img => {
          const k = parseFloat(img.dataset.parallax) || 0.3;
          // Compose parallax with the existing ±20px stagger via CSS variable
          img.style.translate = `0 ${(-t * 12 * k).toFixed(2)}px`;
        });
        ticking = false;
      };
      window.addEventListener('scroll', () => {
        if (!ticking) { requestAnimationFrame(update); ticking = true; }
      }, { passive: true });
      update();
    }
  }
})();
