// Generates the QR code shown on the title and closing slides.
//
// It encodes the deck's public URL so people in the room can scan it and open
// the slides on their own device. The URL defaults to this repo's GitHub Pages
// address but can be overridden with the SLIDES_URL env var (e.g. for a custom
// domain or a fork).
import QRCode from 'qrcode';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const url = process.env.SLIDES_URL || 'https://brodul.github.io/cloudwatch-presentation/';

const here = dirname(fileURLToPath(import.meta.url));
const outFile = resolve(here, '..', 'assets', 'qr-code.svg');

const svg = await QRCode.toString(url, {
  type: 'svg',
  errorCorrectionLevel: 'M',
  margin: 1,
  // White modules on transparent stay readable on reveal.js' dark theme.
  color: { dark: '#000000ff', light: '#ffffffff' },
});

await mkdir(dirname(outFile), { recursive: true });
await writeFile(outFile, svg, 'utf8');

console.log(`Wrote ${outFile} for ${url}`);
