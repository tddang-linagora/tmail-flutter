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

  var SIZES = [9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 24, 32, 48];
  var sizeHeights = {};
  ['sans-serif', 'serif', 'monospace'].forEach(function (font) {
    sizeHeights[font] = SIZES.map(function (px) { return textBox(font, px).height; });
  });

  var content = document.querySelector('.tmail-content') || document.body;
  var probes = {};
  var heights = {};
  FONTS.forEach(function (font) {
    var box = textBox(font, 16);
    probes[font] = box.width;
    heights[font] = box.height;
  });

  return JSON.stringify({
    // Body bottom, not scrollHeight: that one also grows to the viewport, which differs per side.
    scrollHeight: Math.ceil(document.body.getBoundingClientRect().bottom),
    contentScrollWidth: content.scrollWidth,
    contentClientWidth: content.clientWidth,
    overflowX: content.scrollWidth > content.clientWidth + 1,
    probes: probes,
    heights: heights,
    sizeHeights: sizeHeights,
    bodyFont: getComputedStyle(document.body).fontFamily + ' ' + getComputedStyle(document.body).fontSize + ' ' + getComputedStyle(document.body).lineHeight,
    tinyTextHeight: textBox('sans-serif', 4).height,
    maxDeviceWidth480: matchMedia('(max-device-width: 480px)').matches,
    pointerCoarse: matchMedia('(pointer: coarse)').matches,
    hoverNone: matchMedia('(hover: none)').matches,
    dpr: window.devicePixelRatio,
    responsiveScaled: document.querySelectorAll('.tmail-responsive-scale').length,
  });
})
