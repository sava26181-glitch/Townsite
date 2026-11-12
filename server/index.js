// Empire City Online — сервер мультиплеера (WebSocket). Деплой: Render.com (Web Service).
const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 10000;
const clients = new Map();
let nextId = 1;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(`Empire City server OK. Игроков онлайн: ${clients.size}`);
});

const wss = new WebSocketServer({ server });

function send(ws, obj) {
  if (ws.readyState === 1) ws.send(JSON.stringify(obj));
}
function broadcast(obj, exceptId) {
  const msg = JSON.stringify(obj);
  for (const c of clients.values()) {
    if (c.id !== exceptId && c.ws.readyState === 1) c.ws.send(msg);
  }
}
function sendCount() {
  broadcast({ t: 'count', n: clients.size });
}

wss.on('connection', (ws) => {
  const id = String(nextId++);
  const c = { ws, id, name: 'Игрок', state: null, alive: true, lastMsg: 0, msgCount: 0 };
  clients.set(id, c);
  send(ws, { t: 'welcome', id });
  for (const o of clients.values()) if (o.id !== id && o.state) send(ws, o.state);
  sendCount();

  ws.on('pong', () => { c.alive = true; });
  ws.on('message', (raw) => {
    // простая защита от флуда
    const now = Date.now();
    if (now - c.lastMsg > 1000) { c.lastMsg = now; c.msgCount = 0; }
    if (++c.msgCount > 60) return;
    let d;
    try { d = JSON.parse(raw); } catch { return; }
    if (!d || typeof d !== 'object') return;
    switch (d.t) {
      case 'hello':
        c.name = String(d.name || 'Игрок').slice(0, 16);
        broadcast({ t: 'chat', name: 'Сервер', text: `${c.name} зашёл в город` });
        break;
      case 'state': {
        const p = Array.isArray(d.p) ? d.p.slice(0, 3).map(Number) : [0, 0, 0];
        c.state = { t: 'state', id, name: c.name, p, r: Number(d.r) || 0,
          car: String(d.car || '').slice(0, 12), col: String(d.col || '').slice(0, 9), dead: !!d.dead };
        broadcast(c.state, id);
        break;
      }
      case 'chat':
        broadcast({ t: 'chat', name: c.name, text: String(d.text || '').slice(0, 120) });
        break;
      case 'hit': {
        const tgt = clients.get(String(d.target));
        if (tgt) send(tgt.ws, { t: 'hit', from: id, fromName: c.name, dmg: Math.min(50, Math.max(0, Number(d.dmg) || 0)) });
        break;
      }
      case 'killed': {
        const killer = clients.get(String(d.by));
        broadcast({ t: 'chat', name: 'Сервер', text: `${killer ? killer.name : 'Кто-то'} убил ${c.name}` });
        break;
      }
      case 'dead':
        break;
    }
  });
  ws.on('close', () => {
    clients.delete(id);
    broadcast({ t: 'leave', id });
    broadcast({ t: 'chat', name: 'Сервер', text: `${c.name} покинул город` });
    sendCount();
  });
});

setInterval(() => {
  for (const c of clients.values()) {
    if (!c.alive) { c.ws.terminate(); continue; }
    c.alive = false;
    c.ws.ping();
  }
}, 30000);

server.listen(PORT, () => console.log(`Empire City server on :${PORT}`));
