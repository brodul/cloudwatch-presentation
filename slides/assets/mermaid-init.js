(function () {
  function renderAll() {
    var nodes = document.querySelectorAll('code.mermaid:not([data-processed])');
    if (!nodes.length || !window.mermaid) return;

    var restores = [];
    nodes.forEach(function (node) {
      var section = node.closest('section');
      if (section && getComputedStyle(section).display === 'none') {
        restores.push({ el: section, prev: section.style.display });
        section.style.display = 'block';
      }
    });

    window.mermaid.initialize({
      startOnLoad: false,
      theme: 'dark',
      flowchart: { htmlLabels: false },
    });
    window.mermaid.run({ nodes: nodes }).finally(function () {
      restores.forEach(function (r) { r.el.style.display = r.prev; });
      if (window.Reveal) Reveal.layout();
    });
  }

  function init() {
    renderAll();
    if (window.Reveal) {
      Reveal.on('ready', renderAll);
      Reveal.on('slidechanged', renderAll);
    }
  }

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(init, 0);
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();
