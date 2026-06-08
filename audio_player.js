document.addEventListener('keydown', e => {
    if ('t' === e.key) {
        Reveal.getCurrentSlide().getElementsByClassName("media_example")[0].play()
      } else if ('y' === e.key) {
        Reveal.getCurrentSlide().getElementsByClassName("media_example")[0].pause()
      } else if ('u' === e.key) {
        Reveal.getCurrentSlide().getElementsByClassName("media_example")[0].currentTime = 0;
      };
    });