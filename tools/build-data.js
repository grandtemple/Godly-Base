/* Rebuild the inlined data block in web/hero-os.html from db/seed.json.
   The OS ships as one file with no build step, so the data is embedded — but
   it is embedded FROM the seed, never hand-edited, so the interface and the
   database always show the same rows.

     node tools/build-data.js */
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const seed = JSON.parse(fs.readFileSync(path.join(root, "db/seed.json"), "utf8"));
const file = path.join(root, "web/hero-os.html");
const html = fs.readFileSync(file, "utf8");

const open = html.indexOf("<script>");
const close = html.indexOf("</script>", open) + "</script>".length;
if (open < 0 || close < 0) { console.error("no data block found"); process.exit(1); }

const block = `<script>
/* Data. Generated from db/seed.json — the same rows scripts/load_seed.py
   puts into Postgres, so the interface and the database cannot drift.
   Regenerate: node tools/build-data.js */
const DB = ${JSON.stringify(seed, null, 1)};
</script>`;

fs.writeFileSync(file, html.slice(0, open) + block + html.slice(close));
const rows = Object.entries(seed).filter(([,v]) => Array.isArray(v)).reduce((t,[,v]) => t + v.length, 0);
console.log(`web/hero-os.html data block rebuilt: ${Object.keys(seed).length} keys, ${rows} rows`);
