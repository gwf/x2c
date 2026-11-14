// Keep navigation and metadata above the full-height source.
const versionSteps = document.createElement('nav');
versionSteps.className = 'version-steps';
versionSteps.setAttribute('aria-label', 'Step through versions');
versionSteps.innerHTML = '<button id="previous-version">\u2190 Previous</button><span id="version-position"></span><button id="next-version">Next \u2192</button>';
document.querySelector('.sidebar').append(versionSteps);
const updateSteps = () => {
  const buttons = [...document.querySelectorAll('[data-version]')];
  const index = buttons.findIndex(button => button.getAttribute('aria-current') === 'true');
  document.getElementById('previous-version').disabled = index <= 0;
  document.getElementById('next-version').disabled = index >= buttons.length - 1;
  document.getElementById('version-position').textContent = `${index + 1} / ${buttons.length}`;
};
for (const [id, step] of [['previous-version', -1], ['next-version', 1]]) {
  document.getElementById(id).addEventListener('click', () => {
    const buttons = [...document.querySelectorAll('[data-version]')];
    const index = buttons.findIndex(button => button.getAttribute('aria-current') === 'true');
    buttons[index + step]?.click();
  });
}
new MutationObserver(updateSteps).observe(document.getElementById('versions'), {childList: true});
updateSteps();
const toolbar = document.querySelector('.toolbar');
const metadata = document.createElement('div');
metadata.className = 'viewer-metadata';
metadata.append(document.getElementById('comparison-title'),
  document.getElementById('counts'), document.getElementById('line-summary'));
toolbar.before(metadata);
const controls = document.createElement('header');
controls.className = 'viewer-controls';
const sidebar = document.querySelector('.sidebar');
sidebar.before(controls);
controls.append(sidebar, metadata, toolbar, document.getElementById('file-headings'));
