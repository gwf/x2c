// Print the built web page; its HTML, fonts, and print CSS own the PDF layout.
import { preview } from 'astro';
import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import { copyFile } from 'node:fs/promises';
import { sitePath } from '../site-config.mjs';

const root = new URL('../', import.meta.url);
const server = await preview({ root: fileURLToPath(root), server: { host: '127.0.0.1', port: 0 } });
let browser;
try {
  browser = await chromium.launch();
  const page = await browser.newPage();
  await page.emulateMedia({ media: 'print' });
  const response = await page.goto(`http://127.0.0.1:${server.port}${sitePath('/cheatsheet/')}`);
  if (!response.ok()) throw new Error(`Cheat sheet returned HTTP ${response.status()}`);
  await page.locator('.sheet-columns').waitFor();
  await page.evaluate(() => document.fonts.ready);
  const output = fileURLToPath(new URL('dist/x2c-cheatsheet.pdf', root));
  await page.pdf({ path: output, preferCSSPageSize: true, printBackground: true,
    displayHeaderFooter: false, tagged: true });
  await copyFile(output, new URL('public/x2c-cheatsheet.pdf', root));
  console.log(`Generated ${output}`);
} finally {
  await browser?.close();
  await server.stop();
}
