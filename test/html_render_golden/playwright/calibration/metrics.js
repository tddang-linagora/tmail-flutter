(function () {
  var PROBE = 'Hamburgefonstiv 0123456789 Ếọ Жд';
  var FONTS = ['sans-serif', 'serif', 'monospace', 'Arial', 'Helvetica', '"Times New Roman"', 'UnknownFont123'];

  function textBox(font, px) {
    var span = document.createElement('span');
    span.style.cssText = 'position:absolute;white-space:nowrap;font-size:' + px + 'px;font-family:' + font;
    span.textContent = PROBE;
    document.body.appendChild(span);
    var box = span.getBoundingClientRect();
    span.remove();
    return box;
  }

  var content = document.querySelector('.tmail-content') || document.body;
  var probes = {};
  FONTS.forEach(function (font) { probes[font] = textBox(font, 16).width; });

  return JSON.stringify({
    scrollHeight: document.documentElement.scrollHeight,
    contentScrollWidth: content.scrollWidth,
    contentClientWidth: content.clientWidth,
    overflowX: content.scrollWidth > content.clientWidth + 1,
    probes: probes,
    tinyTextHeight: textBox('sans-serif', 4).height,
    maxDeviceWidth480: matchMedia('(max-device-width: 480px)').matches,
    pointerCoarse: matchMedia('(pointer: coarse)').matches,
    hoverNone: matchMedia('(hover: none)').matches,
    dpr: window.devicePixelRatio,
    responsiveScaled: document.querySelectorAll('.tmail-responsive-scale').length,
  });
})
