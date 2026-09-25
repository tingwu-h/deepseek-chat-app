#!/usr/bin/env node
/**
 * 下载器（纯 Node 实现，不依赖 PowerShell 的 .NET 网络栈）。
 *
 * 用法：
 *   node download.mjs <URL> <目标文件> [--proxy=http://127.0.0.1:7897] [--sha256=xxxx]
 *   node download.mjs --latest-flutter-version [--channel=stable]
 *   node download.mjs --latest-flutter-url [--channel=stable]
 *
 * 特性：
 *   - 自动跟随 30x 跳转（Adoptium / Gradle / GitHub 都是跳转下载）
 *   - 支持断点续传（.part 文件 + HTTP Range），中断后重跑会接着下
 *   - 可选 SHA256 校验
 *   - 支持经代理下载；直连失败会自动用代理重试
 *   - 进度条输出到 stderr，不污染 stdout
 */
import fs from 'node:fs';
import path from 'node:path';
import https from 'node:https';
import http from 'node:http';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

// ---------------------------------------------------------------- 参数解析
const argv = process.argv.slice(2);
const flags = new Map();
const positional = [];
for (const a of argv) {
  const m = /^--([^=]+)=?(.*)$/.exec(a);
  if (m) flags.set(m[1], m[2] === '' ? 'true' : m[2]);
  else positional.push(a);
}

const proxyUrl = flags.get('proxy') || process.env.HTTPS_PROXY || process.env.HTTP_PROXY || '';
const wantSha = flags.get('sha256');
const channel = flags.get('channel') || 'stable';

const RELEASES_URL =
  'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json';

// ------------------------------------------------------- 从注册表读系统代理
function windowsProxyFromRegistry() {
  if (process.platform !== 'win32') return '';
  try {
    const out = execFileSync(
      'reg',
      [
        'query',
        'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings',
        '/v',
        'ProxyServer',
      ],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
    );
    const m = /ProxyServer\s+REG_SZ\s+(\S+)/.exec(out);
    if (!m) return '';
    const v = m[1].trim();
    return v.includes('://') ? v : `http://${v}`;
  } catch {
    return '';
  }
}

const fallbackProxy = proxyUrl || windowsProxyFromRegistry();

// ------------------------------------------------------------------ 请求
function get(url, { headers = {}, useProxy = false, redirects = 8 } = {}) {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const mod = target.protocol === 'https:' ? https : http;
    const opts = {
      method: 'GET',
      headers: { 'User-Agent': 'deepseek-chat-builder/1.0', ...headers },
      timeout: 60000,
    };
    if (useProxy && fallbackProxy) {
      const p = new URL(fallbackProxy);
      opts.host = p.hostname;
      opts.port = p.port || (p.protocol === 'https:' ? 443 : 80);
      opts.path = target.toString(); // 绝对 URI，HTTP 代理标准用法
      opts.headers.Host = target.host;
      if (p.username) {
        const auth = Buffer.from(`${p.username}:${p.password}`).toString('base64');
        opts.headers['Proxy-Authorization'] = `Basic ${auth}`;
      }
    } else {
      opts.host = target.hostname;
      opts.port = target.port || (target.protocol === 'https:' ? 443 : 80);
      opts.path = `${target.pathname}${target.search}`;
    }

    const req = mod.request(opts, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
        res.resume();
        if (redirects <= 0) return reject(new Error('跳转次数过多'));
        const next = new URL(res.headers.location, target).toString();
        return resolve(get(next, { headers, useProxy, redirects: redirects - 1 }));
      }
      resolve(res);
    });
    req.on('timeout', () => req.destroy(new Error('请求超时')));
    req.on('error', reject);
    req.end();
  });
}

/** 先直连，失败再走代理；网络抖动自动重试 */
async function openWithFallback(url, headers, attempts = 4) {
  let lastError = null;
  for (let i = 0; i < attempts; i++) {
    if (i > 0) {
      const wait = 1000 * i;
      console.error(`\n[retry] 第 ${i} 次重试（${wait}ms 后）：${url}`);
      await new Promise((r) => setTimeout(r, wait));
    }
    try {
      const res = await get(url, { headers });
      if (res.statusCode >= 200 && res.statusCode < 400) return res;
      if (res.statusCode === 403 || res.statusCode === 407) {
        res.resume();
        lastError = new Error(`HTTP ${res.statusCode}`);
        continue;
      }
      if (res.statusCode < 500) return res; // 4xx 交给调用方判断
      res.resume();
      lastError = new Error(`HTTP ${res.statusCode}`);
    } catch (e) {
      lastError = e;
    }
    // 直连失败 → 用代理再试一次
    if (fallbackProxy) {
      try {
        const res = await get(url, { headers, useProxy: true });
        return res;
      } catch (e) {
        lastError = e;
      }
    }
  }
  throw new Error(`无法连接 ${url}：${lastError ? lastError.message : '未知错误'}`);
}

function getBuffer(url, headers = {}) {
  return openWithFallback(url, headers).then(
    (res) =>
      new Promise((resolve, reject) => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          res.resume();
          return reject(new Error(`HTTP ${res.statusCode} ${url}`));
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve(Buffer.concat(chunks)));
        res.on('error', reject);
      }),
  );
}

// ------------------------------------------------------- Flutter 版本清单
async function flutterReleases() {
  const buf = await getBuffer(RELEASES_URL);
  return JSON.parse(buf.toString('utf8'));
}

function pickRelease(rel, wantChannel) {
  const hash = rel.current_release[wantChannel];
  if (!hash) throw new Error(`清单里没有 ${wantChannel} 渠道`);
  const found = rel.releases.find((r) => r.hash === hash);
  if (!found) throw new Error('清单里找不到当前版本记录');
  return found;
}

// ------------------------------------------------------------------- 下载
function human(n) {
  return n > 1024 ** 3
    ? `${(n / 1024 ** 3).toFixed(2)} GB`
    : `${(n / 1024 ** 2).toFixed(1)} MB`;
}

async function download(url, dest, { sha256 } = {}) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  if (fs.existsSync(dest)) {
    if (!sha256) {
      // 目标文件已完整存在，顺手清掉可能残留的 .part
      fs.rmSync(`${dest}.part`, { force: true });
      console.log(`[skip] 已存在：${dest}`);
      return dest;
    }
    const h = await sha256File(dest);
    if (h.toLowerCase() === sha256.toLowerCase()) {
      console.log(`[skip] 已存在且校验通过：${dest}`);
      return dest;
    }
    console.log('[warn] 已存在但校验失败，重新下载');
    fs.rmSync(dest, { force: true });
  }

  const part = `${dest}.part`;
  let start = 0;
  if (fs.existsSync(part)) {
    start = fs.statSync(part).size;
    console.log(`[续传] 已有 ${human(start)}，从断点继续`);
  }

  const headers = start > 0 ? { Range: `bytes=${start}-` } : {};
  let res = await openWithFallback(url, headers);

  if (start > 0 && res.statusCode === 200) {
    // 服务端不支持断点续传，从头来
    fs.rmSync(part, { force: true });
    start = 0;
    res = await openWithFallback(url, {});
  }
  if (res.statusCode >= 300) {
    res.resume();
    throw new Error(`下载失败 HTTP ${res.statusCode} ${url}`);
  }

  const total = Number(res.headers['content-length'] || 0) + start;
  const out = fs.createWriteStream(part, { flags: start > 0 ? 'a' : 'w' });
  let done = start;
  let lastLog = 0;
  let lastLoggedPct = -10;
  let lastBytes = start;
  const started = Date.now();

  await new Promise((resolve, reject) => {
    res.on('data', (chunk) => {
      done += chunk.length;
      if (!out.write(chunk)) res.pause();
      const now = Date.now();
      const pct = total ? (done / total) * 100 : 0;
      // 每 5% 或每 15 秒打印一次，避免刷屏
      if (now - lastLog > 15000 || pct - lastLoggedPct >= 5) {
        lastLog = now;
        lastLoggedPct = pct;
        const speed = (done - lastBytes) / Math.max(1, (now - started) / 1000);
        lastBytes = done;
        process.stderr.write(
          `  ${path.basename(dest)}  ${human(done)} / ${total ? human(total) : '?'}` +
            `  ${total ? `${pct.toFixed(1)}%` : ''}  ${human(speed)}/s\n`,
        );
      }
    });
    out.on('drain', () => res.resume());
    res.on('end', () => out.end(resolve));
    res.on('error', reject);
    out.on('error', reject);
  });
  process.stderr.write(
    `  ${path.basename(dest)}  下载完成 ${human(done)}（用时 ${Math.round((Date.now() - started) / 1000)} 秒）\n`,
  );

  if (total && done !== total) {
    throw new Error(`下载不完整：${human(done)} / ${human(total)}（重跑本命令会继续续传）`);
  }

  fs.renameSync(part, dest);
  console.log(`[done] ${dest}  (${human(fs.statSync(dest).size)})`);

  if (sha256) {
    const h = await sha256File(dest);
    if (h.toLowerCase() !== sha256.toLowerCase()) {
      fs.rmSync(dest, { force: true });
      throw new Error(`SHA256 校验失败：期望 ${sha256}，实际 ${h}`);
    }
    console.log('[ok] SHA256 校验通过');
  }
  return dest;
}

function sha256File(file) {
  return new Promise((resolve, reject) => {
    const h = crypto.createHash('sha256');
    fs.createReadStream(file)
      .on('data', (c) => h.update(c))
      .on('end', () => resolve(h.digest('hex')))
      .on('error', reject);
  });
}

// ------------------------------------------------------------------- main
(async () => {
  if (flags.has('latest-flutter-version')) {
    const rel = await flutterReleases();
    const r = pickRelease(rel, channel);
    process.stdout.write(r.version);
    return;
  }

  if (flags.has('latest-flutter-url')) {
    const rel = await flutterReleases();
    const r = pickRelease(rel, channel);
    process.stdout.write(`${rel.base_url}/${r.archive}`);
    return;
  }

  const [url, dest] = positional;
  if (!url || !dest) {
    console.error('用法: node download.mjs <URL> <目标文件> [--proxy=...] [--sha256=...]');
    process.exit(2);
  }
  if (fallbackProxy) console.log(`[info] 直连失败时将使用代理：${fallbackProxy}`);
  await download(url, dest, { sha256: wantSha });
})().catch((e) => {
  console.error(`\n[error] ${e.message}`);
  process.exit(1);
});
