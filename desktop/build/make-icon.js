const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#26262c"/>
      <stop offset="1" stop-color="#141418"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" rx="180" ry="180" fill="url(#bg)"/>
  <rect x="160" y="360" width="704" height="304" rx="152" ry="152"
        fill="#2a2a32" stroke="rgba(255,255,255,0.10)" stroke-width="6"/>
  <circle cx="320" cy="512" r="60" fill="#ef4444"/>
  <circle cx="320" cy="512" r="60" fill="none" stroke="rgba(239,68,68,0.35)" stroke-width="20"/>
  <g fill="#fca5a5">
    <rect x="500" y="476" width="16" height="72" rx="8"/>
    <rect x="532" y="442" width="16" height="140" rx="8"/>
    <rect x="564" y="464" width="16" height="96" rx="8"/>
    <rect x="596" y="430" width="16" height="164" rx="8"/>
    <rect x="628" y="464" width="16" height="96" rx="8"/>
    <rect x="660" y="484" width="16" height="56" rx="8"/>
    <rect x="692" y="472" width="16" height="80" rx="8"/>
  </g>
</svg>
`;

(async () => {
  const out = path.join(__dirname, 'icon.png');
  await sharp(Buffer.from(svg))
    .resize(1024, 1024)
    .png()
    .toFile(out);
  console.log('wrote', out);

  const iconset = path.join(__dirname, 'icon.iconset');
  fs.mkdirSync(iconset, { recursive: true });
  const sizes = [
    [16, 'icon_16x16.png'],
    [32, 'icon_16x16@2x.png'],
    [32, 'icon_32x32.png'],
    [64, 'icon_32x32@2x.png'],
    [128, 'icon_128x128.png'],
    [256, 'icon_128x128@2x.png'],
    [256, 'icon_256x256.png'],
    [512, 'icon_256x256@2x.png'],
    [512, 'icon_512x512.png'],
    [1024, 'icon_512x512@2x.png']
  ];
  for (const [size, name] of sizes) {
    await sharp(Buffer.from(svg))
      .resize(size, size)
      .png()
      .toFile(path.join(iconset, name));
  }
  console.log('wrote iconset', iconset);
})().catch((e) => { console.error(e); process.exit(1); });
