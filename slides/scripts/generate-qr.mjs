// Generates the QR code shown on the "Follow along" and "Take it home" slides.
//
// It encodes the reference repo's URL so people in the room can scan it and grab
// the repo (slides, Terraform, and docs) on their own device. The URL defaults
// to this GitHub repo but can be overridden with the REPO_URL env var (e.g. for
// a fork).
import QRCode from 'qrcode';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const url = process.env.REPO_URL || 'https://github.com/brodul/cloudwatch-presentation';

const here = dirname(fileURLToPath(import.meta.url));
const outFile = resolve(here, '..', 'assets', 'qr-code.svg');

const svg = await QRCode.toString(url, {
  type: 'svg',
  errorCorrectionLevel: 'M',
  margin: 1,
  // Rendered on a white tile, so plain black-on-white keeps it high-contrast.
  color: { dark: '#000000ff', light: '#ffffffff' },
});

await mkdir(dirname(outFile), { recursive: true });
await writeFile(outFile, svg, 'utf8');

console.log(`Wrote ${outFile} for ${url}`);
