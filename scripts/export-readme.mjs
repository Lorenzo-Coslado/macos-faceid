/** Export the local documentation scenes through an already connected Browser tab.
 * Run via the Browser skill's Node REPL, not a separate browser automation stack.
 * Screenshots from that API are JPEG. GIF conversion is separate and deterministic.
 */
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

export async function exportStills(tab, { root, base = 'http://127.0.0.1:8768' }) {
  const directory = join(root, 'assets/readme');
  await mkdir(directory, { recursive: true });
  for (const [scene, time] of [['sudo', 1.5], ['lock', 1.5], ['onboarding', 0], ['settings', 0], ['setup', 0], ['choice', 0]]) {
    await tab.goto(`${base}/docs/preview/index.html?scene=${scene}&time=${time}&export=1`);
    const rect = await tab.playwright.evaluate(() => {
      const r = document.getElementById('desktop').getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height };
    });
    await writeFile(join(directory, `${scene}.jpg`), await tab.screenshot({ clip: rect }));
  }
}

export async function exportFrames(tab, { root, directory, scene = 'sudo', base = 'http://127.0.0.1:8768', fps = 20, start = 0, end = 120 }) {
  if (!['sudo', 'lock'].includes(scene)) throw new Error('Animated scenes: sudo or lock');
  await mkdir(directory, { recursive: true });
  for (let i = start; i < end; i++) {
    await tab.goto(`${base}/docs/preview/index.html?scene=${scene}&time=${(i / fps).toFixed(3)}&export=1`);
    await writeFile(join(directory, `frame-${String(i).padStart(4, '0')}.jpg`),
      await tab.screenshot({ clip: { x: 0, y: 0, width: 1200, height: 750 } }));
  }
}
