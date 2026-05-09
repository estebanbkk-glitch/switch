// Anthropic API → DeepSeek proxy
// Usage: DEEPSEEK_API_KEY=sk-xxx node deepseek-proxy.js

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const PORT = 4000;
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY || '';
const DEEPSEEK_MODEL = 'deepseek-chat';
const STATS_FILE = path.join(__dirname, 'deepseek-stats.json');

// -- token usage tracking --
function loadStats() {
  try { return JSON.parse(fs.readFileSync(STATS_FILE, 'utf8')); }
  catch { return { deepseek: { input: 0, output: 0, requests: 0 } }; }
}
function saveStats(stats) { fs.writeFileSync(STATS_FILE, JSON.stringify(stats, null, 2)); }
function trackDeepSeek(inTokens, outTokens) {
  const s = loadStats(); s.deepseek.input += inTokens || 0; s.deepseek.output += outTokens || 0; s.deepseek.requests++; saveStats(s);
}

function convertMessages(msgs, system) {
  const out = [];
  if (system) {
    const text = typeof system === 'string' ? system
      : Array.isArray(system) ? system.filter(b => b.type === 'text').map(b => b.text).join('\n')
      : '';
    if (text) out.push({ role: 'system', content: text });
  }
  for (const msg of msgs) {
    if (msg.role === 'user') {
      if (typeof msg.content === 'string') {
        out.push({ role: 'user', content: msg.content });
      } else {
        const toolResults = msg.content.filter(b => b.type === 'tool_result');
        const textBlocks = msg.content.filter(b => b.type === 'text');
        for (const tr of toolResults) {
          const c = typeof tr.content === 'string' ? tr.content
            : Array.isArray(tr.content) ? tr.content.filter(b => b.type === 'text').map(b => b.text).join('\n') : '';
          out.push({ role: 'tool', content: c, tool_call_id: tr.tool_use_id });
        }
        if (textBlocks.length) out.push({ role: 'user', content: textBlocks.map(b => b.text).join('\n') });
      }
    } else if (msg.role === 'assistant') {
      if (typeof msg.content === 'string') {
        out.push({ role: 'assistant', content: msg.content });
      } else {
        const texts = msg.content.filter(b => b.type === 'text');
        const uses = msg.content.filter(b => b.type === 'tool_use');
        const m = { role: 'assistant', content: texts.length ? texts.map(b => b.text).join('\n') : null };
        if (uses.length) m.tool_calls = uses.map(b => ({ id: b.id, type: 'function', function: { name: b.name, arguments: JSON.stringify(b.input) } }));
        out.push(m);
      }
    }
  }
  return out;
}

function convertTools(tools) {
  if (!tools?.length) return undefined;
  return tools.map(t => ({ type: 'function', function: { name: t.name, description: t.description, parameters: t.input_schema } }));
}

function convertToolChoice(tc) {
  if (!tc) return undefined;
  if (tc.type === 'auto') return 'auto';
  if (tc.type === 'any') return 'required';
  if (tc.type === 'tool') return { type: 'function', function: { name: tc.name } };
  return 'auto';
}

function convertResponse(r, model) {
  const choice = r.choices[0];
  const msg = choice.message;
  const content = [];
  if (msg.content) content.push({ type: 'text', text: msg.content });
  if (msg.tool_calls) {
    for (const tc of msg.tool_calls) {
      content.push({ type: 'tool_use', id: tc.id, name: tc.function.name, input: JSON.parse(tc.function.arguments || '{}') });
    }
  }
  const stop_reason = choice.finish_reason === 'tool_calls' ? 'tool_use' : choice.finish_reason === 'length' ? 'max_tokens' : 'end_turn';
  return { id: r.id || `msg_${Date.now()}`, type: 'message', role: 'assistant', content, model: model || DEEPSEEK_MODEL, stop_reason, usage: { input_tokens: r.usage?.prompt_tokens || 0, output_tokens: r.usage?.completion_tokens || 0 } };
}

function handleStreaming(res, upstream, model, onDone) {
  const msgId = `msg_${Date.now()}`;
  res.write(`event: message_start\ndata: ${JSON.stringify({ type: 'message_start', message: { id: msgId, type: 'message', role: 'assistant', content: [], model, stop_reason: null, usage: { input_tokens: 0, output_tokens: 0 } } })}\n\n`);

  let textStarted = false, toolBlocks = {}, buf = '', finalOut = 0;

  upstream.on('data', chunk => {
    buf += chunk.toString();
    const lines = buf.split('\n');
    buf = lines.pop();
    for (const line of lines) {
      if (!line.startsWith('data: ')) continue;
      const raw = line.slice(6).trim();
      if (raw === '[DONE]') { res.write(`event: message_stop\ndata: ${JSON.stringify({ type: 'message_stop' })}\n\n`); res.end(); return; }
      let p; try { p = JSON.parse(raw); } catch { continue; }
      const choice = p.choices?.[0]; if (!choice) continue;
      const delta = choice.delta || {};

      if (delta.content != null) {
        if (!textStarted) { textStarted = true; res.write(`event: content_block_start\ndata: ${JSON.stringify({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } })}\n\n`); }
        if (delta.content) res.write(`event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: delta.content } })}\n\n`);
      }

      if (delta.tool_calls) {
        for (const tc of delta.tool_calls) {
          const i = tc.index, bi = (textStarted ? 1 : 0) + i;
          if (tc.id) { toolBlocks[i] = { id: tc.id, name: tc.function?.name || '' }; if (textStarted && !Object.keys(toolBlocks).length) { res.write(`event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: 0 })}\n\n`); } res.write(`event: content_block_start\ndata: ${JSON.stringify({ type: 'content_block_start', index: bi, content_block: { type: 'tool_use', id: tc.id, name: tc.function?.name || '', input: {} } })}\n\n`); }
          if (tc.function?.arguments) res.write(`event: content_block_delta\ndata: ${JSON.stringify({ type: 'content_block_delta', index: bi, delta: { type: 'input_json_delta', partial_json: tc.function.arguments } })}\n\n`);
        }
      }

      if (choice.finish_reason) {
        if (textStarted) res.write(`event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: 0 })}\n\n`);
        for (const i of Object.keys(toolBlocks)) res.write(`event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: (textStarted ? 1 : 0) + parseInt(i) })}\n\n`);
        const stop_reason = choice.finish_reason === 'tool_calls' ? 'tool_use' : choice.finish_reason === 'length' ? 'max_tokens' : 'end_turn';
        finalOut = p.usage?.completion_tokens || 0;
        res.write(`event: message_delta\ndata: ${JSON.stringify({ type: 'message_delta', delta: { stop_reason }, usage: { output_tokens: finalOut } })}\n\n`);
      }
    }
  });

  upstream.on('end', () => {
    if (!res.writableEnded) { res.write(`event: message_stop\ndata: ${JSON.stringify({ type: 'message_stop' })}\n\n`); res.end(); }
    if (onDone) onDone(0, finalOut);
  });
  upstream.on('error', () => { if (!res.writableEnded) res.end(); if (onDone) onDone(0, 0); });
}

const FAKE_MODELS = ['claude-sonnet-4-6', 'claude-opus-4-7', 'claude-haiku-4-5-20251001'];

const fs = require('fs');
const logFile = require('path').join(__dirname, 'proxy.log');
function log(msg) { const line = `${new Date().toISOString()} ${msg}\n`; process.stdout.write(line); fs.appendFileSync(logFile, line); }

const server = http.createServer((req, res) => {
  log(`${req.method} ${req.url}`);
  if (req.method === 'GET' && req.url === '/health') { res.writeHead(200); res.end(JSON.stringify({ status: 'ok' })); return; }

  if (req.method === 'GET' && req.url === '/v1/models') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ data: FAKE_MODELS.map(id => ({ id, object: 'model', created: 0, owned_by: 'proxy' })) }));
    return;
  }

  if (req.method === 'GET' && req.url === '/v1/stats') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(loadStats()));
    return;
  }
  if (req.method === 'GET' && req.url === '/v1/stats/reset') {
    const empty = { deepseek: { input: 0, output: 0, requests: 0 } };
    saveStats(empty); res.writeHead(200); res.end(JSON.stringify(empty));
    return;
  }
  if (req.method === 'HEAD') { res.writeHead(200); res.end(); return; }
  if (req.method !== 'POST' || !req.url.startsWith('/v1/messages')) { res.writeHead(404); res.end(); return; }

  let body = '';
  req.on('data', c => body += c);
  req.on('end', () => {
    let ar; try { ar = JSON.parse(body); } catch { res.writeHead(400); res.end(); return; }
    const apiKey = DEEPSEEK_API_KEY || req.headers['x-api-key'] || '';
    const oReq = { model: DEEPSEEK_MODEL, messages: convertMessages(ar.messages, ar.system), max_tokens: ar.max_tokens, stream: ar.stream || false };
    if (ar.temperature != null) oReq.temperature = ar.temperature;
    if (ar.top_p != null) oReq.top_p = ar.top_p;
    const tools = convertTools(ar.tools); if (tools) oReq.tools = tools;
    const tc = convertToolChoice(ar.tool_choice); if (tc) oReq.tool_choice = tc;
    const reqBody = JSON.stringify(oReq);

    const upReq = https.request({ hostname: 'api.deepseek.com', path: '/chat/completions', method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}`, 'Content-Length': Buffer.byteLength(reqBody) } }, upRes => {
      if (oReq.stream) {
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
        // wrap handleStreaming to track final usage
        const origEnd = res.end.bind(res);
        let finalIn = 0, finalOut = 0;
        res.end = function(...args) {
          trackDeepSeek(finalIn, finalOut);
          return origEnd(...args);
        };
        handleStreaming(res, upRes, ar.model, (inTok, outTok) => { finalIn = inTok; finalOut = outTok; });
      } else {
        let rb = ''; upRes.on('data', c => rb += c); upRes.on('end', () => {
          try {
            const or = JSON.parse(rb);
            if (or.error) { res.writeHead(upRes.statusCode || 500, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ type: 'error', error: { type: 'api_error', message: or.error.message } })); return; }
            trackDeepSeek(or.usage?.prompt_tokens || 0, or.usage?.completion_tokens || 0);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(convertResponse(or, ar.model)));
          } catch (e) { res.writeHead(500); res.end(JSON.stringify({ error: e.message })); }
        });
      }
    });
    upReq.on('error', e => { log(`ERROR ${e.message}`); res.writeHead(502); res.end(JSON.stringify({ error: e.message })); });
    upReq.write(reqBody); upReq.end();
  });
});

server.listen(PORT, () => {
  const keyHint = DEEPSEEK_API_KEY ? DEEPSEEK_API_KEY.slice(0, 8) + '...' : 'NOT SET - pass via DEEPSEEK_API_KEY env var';
  console.log(`DeepSeek proxy on http://localhost:${PORT}`);
  console.log(`API key: ${keyHint}`);
});
server.on('error', e => { console.error(e.code === 'EADDRINUSE' ? `Port ${PORT} already in use` : e); process.exit(1); });
