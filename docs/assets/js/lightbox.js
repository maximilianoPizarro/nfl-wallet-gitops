(function () {
  function initLightbox() {
    var overlay = document.getElementById('lightbox-overlay');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'lightbox-overlay';
      overlay.className = 'lightbox-overlay';
      var img = document.createElement('img');
      img.alt = '';
      overlay.appendChild(img);
      var close = document.createElement('button');
      close.className = 'lightbox-close';
      close.setAttribute('type', 'button');
      close.setAttribute('aria-label', 'Close');
      close.innerHTML = '&times;';
      overlay.appendChild(close);
      document.body.appendChild(overlay);

      function closeLightbox() {
        overlay.classList.remove('is-open');
        document.body.style.overflow = '';
      }

      overlay.addEventListener('click', function (e) {
        if (e.target === overlay || e.target.classList.contains('lightbox-close')) {
          closeLightbox();
        }
      });
      overlay.querySelector('img').addEventListener('click', function (e) {
        e.stopPropagation();
      });
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && overlay.classList.contains('is-open')) {
          closeLightbox();
        }
      });

      var content = document.querySelector('.post-content');
      if (content) {
        content.querySelectorAll('img').forEach(function (img) {
          img.addEventListener('click', function (e) {
            e.preventDefault();
            overlay.querySelector('img').src = img.currentSrc || img.src;
            overlay.querySelector('img').alt = img.alt || 'Enlarged image';
            overlay.classList.add('is-open');
            document.body.style.overflow = 'hidden';
          });
        });
      }
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initLightbox);
  } else {
    initLightbox();
  }
})();
