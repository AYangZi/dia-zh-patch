#!/usr/bin/env node
// 从本机已安装的 Dia.app 推导某个 Build 的 WebUI 清单。
//
// 用法：
//   node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version 1.53.0 --build 88760
//   node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --version 1.53.0 --build 88760 --write
//   node scripts/derive-webui-manifest.mjs --app /Applications/Dia.app --check manifests/1.53.0-88760.json
//
// 推导思路：WebUI 规则只从统一词表 `translations/zh-Hans.strings` 里取，
// 因此新增 Build 支持时不需要再手写译文；脚本负责把「词表里真实出现在该 Build
// WebUI 文件中的条目」变成带精确匹配次数的规则，并同步生成原始/补丁后哈希清单。
// 任何计数对不上都会在 apply 前被 patch-webui.jxa 拦住，不会静默改错文件。

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..");

function die(message) {
  console.error(`[derive] 错误：${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const options = {
    app: "/Applications/Dia.app",
    version: "",
    build: "",
    catalog: path.join(repoRoot, "translations", "zh-Hans.strings"),
    outDir: path.join(repoRoot, "manifests"),
    check: "",
    write: false,
    report: "",
    roots: ""
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    const next = () => {
      const value = argv[index + 1];
      if (value == null) die(`${token} 缺少取值`);
      index += 1;
      return value;
    };
    switch (token) {
      case "--app": options.app = next(); break;
      case "--version": options.version = next(); break;
      case "--build": options.build = next(); break;
      case "--catalog": options.catalog = next(); break;
      case "--out-dir": options.outDir = next(); break;
      case "--check": options.check = next(); break;
      case "--report": options.report = next(); break;
      case "--roots": options.roots = next(); break;
      case "--write": options.write = true; break;
      case "-h":
      case "--help":
        console.log(fs.readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").slice(1, 20).join("\n"));
        process.exit(0);
        break;
      default:
        die(`未知参数：${token}`);
    }
  }
  return options;
}

const EXCLUDED_FRAGMENTS = [".map", "/agents/", "/prompts/", "-prompt.txt", "/spec.yaml"];
const WEB_EXTENSIONS = [".js", ".html"];
const SKIP_DIRECTORIES = new Set(["DevTools", "__pycache__", ".git"]);
// 库/演示/许可证类资源不参与汉化：既不做规则，也不进哈希清单。
const SKIP_ROOT_PATTERNS = [/^Highlightr_/, /^SDWebImage/, /^BoostBrowser_SupertabEngine(?:\.bundle)?$/, /^DevTools$/];
const SKIP_FILE_PATTERNS = [/credits/i, /licen[cs]e/i, /third[_-]?party/i, /\.min\.js$/i];

function isSkippedRoot(name) {
  return SKIP_ROOT_PATTERNS.some((pattern) => pattern.test(name));
}

function isSkippedFile(name) {
  return SKIP_FILE_PATTERNS.some((pattern) => pattern.test(name));
}
const CRITICAL_CANDIDATES = [
  "Contents/MacOS/Dia",
  "Contents/Info.plist",
  "Contents/Frameworks/ArcCore.framework/Versions/A/Resources/zh_CN.lproj/locale.pak",
  "Contents/Frameworks/ArcCore.framework/Versions/A/Resources/en.lproj/locale.pak",
  "Contents/Resources/web-chat-resources/dist/index.html",
  "Contents/Resources/web-chat-resources/dist/background.js",
  "Contents/Resources/web-chat-resources/dist/manifest.json",
  "Contents/Resources/BoostBrowser_WelcomePostcardBundle.bundle/Contents/Resources/site/index.html",
  "Contents/Resources/BoostBrowser_MorningBriefTeaserBundle.bundle/Contents/Resources/site/index.html"
];

function plistValue(appPath, key) {
  try {
    return execFileSync(
      "/usr/libexec/PlistBuddy",
      ["-c", `Print :${key}`, path.join(appPath, "Contents", "Info.plist")],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }
    ).trim();
  } catch {
    return "";
  }
}

function mainBinaryArchitectures(appPath) {
  const binary = path.join(appPath, "Contents", "MacOS", "Dia");
  if (!fs.existsSync(binary)) die("缺少主程序 Mach-O");
  try {
    return execFileSync("lipo", ["-archs", binary], { encoding: "utf8" }).trim();
  } catch {
    return "";
  }
}

function isExcluded(relative) {
  const normalized = relative.replace(/\\/g, "/");
  return EXCLUDED_FRAGMENTS.some((fragment) => normalized.includes(fragment));
}

function isWebFile(name) {
  return WEB_EXTENSIONS.includes(path.extname(name).toLowerCase());
}

// 在 Contents/Resources 下找出「最上层的、包含 WebUI 文本文件」的目录作为扫描根。
function discoverRoots(appPath) {
  const resourceRoot = path.join(appPath, "Contents", "Resources");
  if (!fs.existsSync(resourceRoot)) die("缺少 Contents/Resources");
  const roots = [];

  function containsTextFile(directory, relative) {
    let found = false;
    for (const name of fs.readdirSync(directory)) {
      const childRelative = relative ? `${relative}/${name}` : name;
      const childFull = path.join(directory, name);
      if (isExcluded(childRelative)) continue;
      const stat = fs.statSync(childFull);
      if (stat.isDirectory()) {
        if (SKIP_DIRECTORIES.has(name) || isSkippedRoot(name)) continue;
        if (containsTextFile(childFull, childRelative)) found = true;
      } else if (isWebFile(name) && !isSkippedFile(name)) {
        found = true;
      }
    }
    return found;
  }

  function walk(directory, relative) {
    for (const name of fs.readdirSync(directory)) {
      const childRelative = relative ? `${relative}/${name}` : name;
      const childFull = path.join(directory, name);
      if (isExcluded(childRelative)) continue;
      const stat = fs.statSync(childFull);
      if (!stat.isDirectory()) continue;
      if (SKIP_DIRECTORIES.has(name) || isSkippedRoot(name)) continue;
      if (containsTextFile(childFull, childRelative)) {
        roots.push(`Contents/Resources/${childRelative}`);
      } else {
        walk(childFull, childRelative);
      }
    }
  }

  walk(resourceRoot, "");
  return roots.sort();
}

function collectFiles(appPath, roots) {
  const files = [];
  const perRoot = new Map();
  for (const root of roots) {
    const absoluteRoot = path.join(appPath, root);
    const collected = [];
    const walk = (directory, relative) => {
      for (const name of fs.readdirSync(directory).sort()) {
        const childRelative = relative ? `${relative}/${name}` : name;
        const childFull = path.join(directory, name);
        if (isExcluded(`${root}/${childRelative}`)) continue;
        const stat = fs.statSync(childFull);
        if (stat.isDirectory()) walk(childFull, childRelative);
        else if (isWebFile(name) && !isSkippedFile(name)) collected.push({
          relativePath: `${root}/${childRelative}`,
          absolutePath: childFull
        });
      }
    };
    walk(absoluteRoot, "");
    collected.sort((a, b) => a.relativePath.localeCompare(b.relativePath));
    perRoot.set(root, collected.length);
    files.push(...collected);
  }
  files.sort((a, b) => a.relativePath.localeCompare(b.relativePath));
  return { files, perRoot };
}

function parseCatalog(catalogPath) {
  const text = fs.readFileSync(catalogPath, "utf8");
  const entries = [];
  const seen = new Set();
  for (const match of text.matchAll(/^"((?:\\.|[^"])*)"\s*=\s*"((?:\\.|[^"])*)";$/gm)) {
    const source = match[1].replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    const target = match[2].replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    if (seen.has(source)) die(`词表存在重复键：${source}`);
    seen.add(source);
    entries.push({ source, target });
  }
  return entries;
}

function ruleVariants(source, target) {
  const escapedSource = source.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const escapedTarget = target.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const singleSource = source.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
  const singleTarget = target.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
  return [
    { find: `"${escapedSource}"`, replace: `"${escapedTarget}"` },
    { find: `'${singleSource}'`, replace: `'${singleTarget}'` },
    { find: `>${source}<`, replace: `>${target}<` },
    { find: `&quot;${source}&quot;`, replace: `&quot;${target}&quot;` }
  ];
}

function countOccurrences(text, needle) {
  if (!needle) return 0;
  return text.split(needle).length - 1;
}

function slugify(source) {
  const slug = source
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
  return slug || "rule";
}

function buildManifest(options) {
  const appPath = path.resolve(options.app);
  const version = options.version || plistValue(appPath, "CFBundleShortVersionString");
  const build = options.build || plistValue(appPath, "CFBundleVersion");
  if (!version || !build) die("无法确定版本号，请显式传 --version/--build");

  const bundleId = plistValue(appPath, "CFBundleIdentifier");
  if (bundleId !== "company.thebrowser.dia") die(`Bundle ID 不是 Dia：${bundleId}`);
  const architectures = mainBinaryArchitectures(appPath);
  if (!architectures.split(/\s+/).includes("arm64")) die(`主程序缺少 arm64 架构：${architectures}`);

  const roots = options.roots
    ? options.roots.split(",").map((item) => item.trim()).filter(Boolean)
    : discoverRoots(appPath);
  if (roots.length === 0) die("没有发现任何 WebUI 目录");
  for (const root of roots) {
    if (!fs.existsSync(path.join(appPath, root))) die(`WebUI 目录不存在：${root}`);
  }
  const { files, perRoot } = collectFiles(appPath, roots);
  if (files.length === 0) die("WebUI 目录里没有 .js/.html 文件");

  const contents = new Map();
  for (const file of files) contents.set(file.relativePath, fs.readFileSync(file.absolutePath, "utf8"));

  const catalog = parseCatalog(options.catalog);
  const usedIds = new Set();
  const rules = [];
  for (const entry of catalog) {
    if (entry.source === entry.target) continue;
    if (entry.source.length <= 2) continue;
    const variants = ruleVariants(entry.source, entry.target);
    const matched = [];
    let total = 0;
    for (const file of files) {
      const text = contents.get(file.relativePath);
      let count = 0;
      for (const variant of variants) count += countOccurrences(text, variant.find);
      if (count > 0) {
        matched.push({ path: file.relativePath, matches: count });
        total += count;
      }
    }
    if (total === 0) continue;
    let id = `web.${slugify(entry.source)}`;
    let suffix = 2;
    while (usedIds.has(id)) id = `web.${slugify(entry.source)}-${suffix++}`;
    usedIds.add(id);
    rules.push({ id, source: entry.source, target: entry.target, files: matched, expectedMatches: total });
  }

  // 模拟整轮替换，得到补丁后的精确计数（同一译文可能被多条规则重复计数）。
  const patched = new Map(contents);
  for (const rule of rules) {
    const variants = ruleVariants(rule.source, rule.target);
    for (const file of rule.files) {
      let text = patched.get(file.path);
      for (const variant of variants) text = text.split(variant.find).join(variant.replace);
      patched.set(file.path, text);
    }
  }
  for (const rule of rules) {
    const variants = ruleVariants(rule.source, rule.target).map((variant) => variant.replace);
    let patchedTotal = 0;
    for (const file of rule.files) {
      const text = patched.get(file.path);
      let count = 0;
      for (const variant of variants) count += countOccurrences(text, variant);
      file.patchedMatches = count;
      patchedTotal += count;
    }
    rule.expectedPatchedMatches = patchedTotal;
    // patch-webui.jxa 要求补丁后文件里不再残留源串
    for (const file of rule.files) {
      const text = patched.get(file.path);
      for (const variant of ruleVariants(rule.source, rule.target)) {
        if (countOccurrences(text, variant.find) > 0) die(`${rule.id} 补丁后仍残留源串：${file.path}`);
      }
    }
  }
  if (rules.length === 0) die("词表在该 Build 的 WebUI 里一条都没命中");

  const criticalFiles = CRITICAL_CANDIDATES
    .map((relative) => ({ path: relative, absolute: path.join(appPath, relative) }))
    .filter((item) => fs.existsSync(item.absolute))
    .map((item) => ({ path: item.path, bytes: fs.statSync(item.absolute).size }));
  if (criticalFiles.length < 5) die("关键资源不足，拒绝生成清单");

  const minimumTotal = rules.reduce((sum, rule) => sum + rule.expectedMatches, 0);
  const expectedTotalPatched = rules.reduce((sum, rule) => sum + rule.expectedPatchedMatches, 0);

  const manifest = {
    schemaVersion: 1,
    product: "Dia",
    bundleIdentifier: bundleId,
    officialTeamIdentifier: plistValue(appPath, "DiaOfficialTeamIdentifier") || "S6N382Y83G",
    shortVersion: version,
    buildVersion: build,
    minimumMacOS: plistValue(appPath, "LSMinimumSystemVersion") || "14.0",
    architecture: "arm64",
    criticalFiles,
    chromiumLocale: {
      source: "Contents/Frameworks/ArcCore.framework/Versions/A/Resources/zh_CN.lproj/locale.pak",
      destination: "Contents/Frameworks/ArcCore.framework/Versions/A/Resources/en.lproj/locale.pak",
      minimumBytes: 500000
    },
    localization: {
      stringsFile: "translations/zh-Hans.strings",
      mainResourceDirectory: "Contents/Resources",
      bundleRoot: "Contents/Resources",
      bundleNamePrefixes: ["BoostBrowser_", "ARC_", "ARCUI_", "ARCClients_"],
      localeDirectories: ["en.lproj", "zh-Hans.lproj"]
    },
    webRoots: roots,
    webRootExpectations: roots.map((root) => ({ path: root, expectedTextFiles: perRoot.get(root) })),
    webExtensions: WEB_EXTENSIONS,
    minimumTotalWebMatches: minimumTotal,
    maximumTotalWebMatches: minimumTotal,
    excludedPathFragments: EXCLUDED_FRAGMENTS,
    webRules: rules,
    webHashManifests: { original: "", patched: "" },
    expectedTotalPatchedMatches: expectedTotalPatched
  };

  const baseName = `${version}-${build}`;
  const originalName = `manifests/${baseName}.webui-original.sha256`;
  const patchedName = `manifests/${baseName}.webui-patched.sha256`;
  manifest.webHashManifests.original = originalName;
  manifest.webHashManifests.patched = patchedName;

  const hashLine = (relative, text) =>
    `${createHash("sha256").update(text, "utf8").digest("hex")}  ${relative}`;
  const originalHashes = files.map((file) => hashLine(file.relativePath, contents.get(file.relativePath)));
  const patchedHashes = files.map((file) => hashLine(file.relativePath, patched.get(file.relativePath)));

  return {
    manifest,
    manifestName: `manifests/${baseName}.json`,
    originalHashes,
    patchedHashes,
    scannedFiles: files.length,
    roots,
    perRoot
  };
}

import { createHash } from "node:crypto";

function writeOutput(options, result) {
  const outDir = options.outDir;
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, `${result.manifest.shortVersion}-${result.manifest.buildVersion}.json`),
    `${JSON.stringify(result.manifest, null, 2)}\n`);
  fs.writeFileSync(path.join(outDir, `${result.manifest.shortVersion}-${result.manifest.buildVersion}.webui-original.sha256`),
    `${result.originalHashes.join("\n")}\n`);
  fs.writeFileSync(path.join(outDir, `${result.manifest.shortVersion}-${result.manifest.buildVersion}.webui-patched.sha256`),
    `${result.patchedHashes.join("\n")}\n`);
}

function summarize(result) {
  const { manifest } = result;
  console.log(`[derive] ${manifest.shortVersion} (${manifest.buildVersion}) · 扫描 ${result.scannedFiles} 个 WebUI 文件 · ${result.roots.length} 个根目录`);
  for (const root of result.roots) console.log(`[derive]   ${result.perRoot.get(root)} 文件  ${root}`);
  console.log(`[derive] 规则 ${manifest.webRules.length} 条 · 匹配 ${manifest.minimumTotalWebMatches} 次 · 补丁后 ${manifest.expectedTotalPatchedMatches} 次`);
  for (const rule of manifest.webRules) {
    console.log(`[derive]   ${String(rule.expectedMatches).padStart(3)} → ${String(rule.expectedPatchedMatches).padStart(3)}  ${rule.source.slice(0, 48)}  ⇒  ${rule.target.slice(0, 24)}`);
  }
}

function checkManifest(options, result) {
  const manifestPath = path.resolve(options.check);
  if (!fs.existsSync(manifestPath)) die(`清单不存在：${manifestPath}`);
  const existing = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const problems = [];
  const compare = (label, actual, expected) => {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) problems.push(`${label} 不一致`);
  };
  compare("shortVersion", existing.shortVersion, result.manifest.shortVersion);
  compare("buildVersion", existing.buildVersion, result.manifest.buildVersion);
  compare("webRoots", existing.webRoots, result.manifest.webRoots);
  compare("webRootExpectations", existing.webRootExpectations, result.manifest.webRootExpectations);
  compare("criticalFiles", existing.criticalFiles, result.manifest.criticalFiles);
  compare("minimumTotalWebMatches", existing.minimumTotalWebMatches, result.manifest.minimumTotalWebMatches);
  compare("webRules", existing.webRules, result.manifest.webRules);
  for (const name of ["original", "patched"]) {
    const relative = existing.webHashManifests?.[name];
    if (!relative) { problems.push(`缺少 ${name} 哈希清单引用`); continue; }
    const file = path.join(repoRoot, relative);
    if (!fs.existsSync(file)) { problems.push(`${name} 哈希清单文件不存在：${relative}`); continue; }
    const expected = fs.readFileSync(file, "utf8").trim().split("\n");
    const actual = name === "original" ? result.originalHashes : result.patchedHashes;
    compare(`${name} 哈希清单`, actual, expected);
  }
  if (problems.length > 0) {
    console.error(`[derive] 清单与当前 Dia 不一致：`);
    for (const problem of problems) console.error(`[derive]   - ${problem}`);
    process.exit(1);
  }
  console.log(`[derive] 清单与当前 Dia 完全一致：${path.relative(repoRoot, manifestPath)}`);
}

const options = parseArgs(process.argv.slice(2));
const result = buildManifest(options);
summarize(result);
if (options.check) {
  checkManifest(options, result);
} else if (options.write) {
  writeOutput(options, result);
  console.log(`[derive] 已写入 ${path.join(options.outDir, `${result.manifest.shortVersion}-${result.manifest.buildVersion}.json`)}`);
} else {
  console.log("[derive] 预演模式：未写入任何文件（加 --write 落盘，加 --check <manifest> 校对已有清单）");
}
