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
  // The printable area of the page in CSS pixels, so the overflow check
  // below measures the layout that the PDF gets.
  const page = await browser.newPage({ viewport: { width: 1008, height: 768 } });
  await page.emulateMedia({ media: 'print' });
  const response = await page.goto(`http://127.0.0.1:${server.port}${sitePath('/cheatsheet/')}`);
  if (!response.ok()) throw new Error(`Cheat sheet returned HTTP ${response.status()}`);
  await page.locator('.sheet-columns').waitFor();
  await page.evaluate(() => document.fonts.ready);
  // Columns have a fixed height, so text that does not fit would spill
  // over the footer instead of starting a second page.
  const spill = await page.locator('.sheet-column').evaluateAll((columns) =>
    Math.max(...columns.map((column) => column.scrollHeight - column.clientHeight)));
  if (spill > 0) throw new Error(`Cheat sheet column overflows by ${spill}px`);
  const output = fileURLToPath(new URL('dist/x2c-cheatsheet.pdf', root));
  await page.pdf({ path: output, preferCSSPageSize: true, printBackground: true,
    displayHeaderFooter: false, tagged: true });
  await copyFile(output, new URL('public/x2c-cheatsheet.pdf', root));
  console.log(`Generated ${output}`);
} finally {
  await browser?.close();
  await server.stop();
}
