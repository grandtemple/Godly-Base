/* Build the OS token block from design-system/tokens.json.
   The generator that ships with the design-system skill flattens aliases to
   raw values and emits dark mode under `.dark`. The OS needs the opposite:
   a live var() chain (so the semantic layer is real at runtime, not just in
   the JSON) and three theme states — bare :root, prefers-color-scheme, and
   an explicit [data-theme] stamp — so the in-page toggle wins both ways.

     node tools/build-tokens.js */
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const T = JSON.parse(fs.readFileSync(path.join(root, "design-system/tokens.json"), "utf8"));

const ref = v => typeof v === "string" && v.startsWith("{")
  ? "var(--" + v.slice(1, -1).replace(/^primitive\./, "primitive-").replace(/^semantic\./, "").replace(/\./g, "-") + ")"
  : v;

const flat = (obj, prefix = []) => Object.entries(obj).flatMap(([k, v]) =>
  v && typeof v === "object" && v.$value === undefined
    ? flat(v, [...prefix, k])
    : [[`--${[...prefix, k].join("-")}`, ref(v.$value)]]);

const lines = pairs => pairs.map(([k, v]) => `  ${k}: ${v};`).join("\n");
const primitives = flat(T.primitive, ["primitive"]);
const semantic   = flat(T.semantic);
const component  = flat(T.component);
const dark       = flat(T.dark.semantic);

const block = `<style>
/* ============================================================
   HERO CAPITAL OS — tokens
   Generated from design-system/tokens.json by tools/build-tokens.js.
   Do not edit here; edit the JSON and rebuild.
   primitive → semantic → component. Nothing below this block
   uses a raw color value.
   ============================================================ */
:root{
  color-scheme: light dark;

  /* ---- primitive ---- */
${lines(primitives)}

  /* ---- semantic ---- */
${lines(semantic)}

  /* ---- component ---- */
${lines(component)}
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
${lines(dark).replace(/^/gm, "  ")}
  }
}
:root[data-theme="dark"]{
${lines(dark)}
}
</style>`;

/* Client-facing surfaces are light-only and print, so they take the same
   primitive/semantic/component chain without the dark overrides. */
const lightBlock = `<style>
/* Tokens — generated from design-system/tokens.json by tools/build-tokens.js.
   Do not edit here. Client-facing surfaces are light-only by design: a
   proposal is read on a screen once and printed twice. */
:root{
  color-scheme: light;
${lines(primitives)}
${lines(semantic)}
${lines(component)}
}
</style>`;

const targets = [
  ["web/hero-os.html", block],
  ["web/proposal-template.html", lightBlock]
];
for (const [rel, css] of targets){
  const file = path.join(root, rel);
  if (!fs.existsSync(file)) continue;
  const html = fs.readFileSync(file, "utf8");
  const open = html.indexOf("<style>");
  const close = html.indexOf("</style>", open) + "</style>".length;
  if (open < 0) { console.error(`no token block in ${rel}`); continue; }
  fs.writeFileSync(file, html.slice(0, open) + css + html.slice(close));
  console.log(`${rel} tokens rebuilt`);
}
console.log(`${primitives.length} primitive, ${semantic.length} semantic, ${component.length} component, ${dark.length} dark overrides`);
