const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../web/webmcp.js'), 'utf8');

function harness() {
  const listeners = {}, timers = new Map();
  let next = 0;
  const document = {addEventListener: (name, cb) => listeners[name] = cb, visibilityState: 'visible'};
  const window = {addEventListener: (name, cb) => listeners[name] = cb};
  const navigator = {};
  const context = {window, document, navigator, console: {warn() {}},
    setTimeout: cb => {timers.set(++next, cb); return next;},
    clearTimeout: id => timers.delete(id)};
  vm.runInNewContext(source, context);
  const drain = async () => {for (let i = 0; i < 80; i++) await Promise.resolve();};
  return {window, document, navigator, listeners, timers, drain,
    async tick() {const entry = timers.entries().next().value; if (entry) {timers.delete(entry[0]); entry[1]();} await drain();},
    async ready() {window.foldboard.setHandler(raw => JSON.stringify({ok: true, tool: JSON.parse(raw).tool}), () => {}); await drain();},
  };
}

test('late document API is retried; repeated events never duplicate registration', async () => {
  const h = harness(), registered = new Map();
  await h.ready();
  assert.equal(h.timers.size, 1);
  h.document.modelContext = {async registerTool(tool) {assert(!registered.has(tool.name)); registered.set(tool.name, tool);}};
  await h.tick();
  assert.equal(registered.size, 18);
  for (const event of ['load', 'focus', 'pageshow', 'visibilitychange']) {h.listeners[event](); await h.drain();}
  await h.ready();
  assert.equal(registered.size, 18);
  assert.equal(JSON.parse(h.window.foldboard.mcpStatus()).registered, 18);
  const result = await registered.get('get-outline').execute({});
  assert.equal(result.tool, 'get-outline');
  assert.equal(registered.get('reveal-card').annotations.readOnlyHint, false);
  assert.equal(registered.get('fit-content').annotations.readOnlyHint, false);
  assert.equal(registered.get('get-user-context').annotations.readOnlyHint, true);
  assert.equal(registered.get('apply-changes').inputSchema.properties.return.default, 'summary');
  assert.equal(registered.get('apply-changes').inputSchema.properties.validate.default, false);
  const changeSchema = registered.get('apply-changes').inputSchema.properties.changes.properties;
  assert.equal(changeSchema.version, undefined);
  assert.equal(changeSchema.revision.minimum, 0);
  const createSchema = registered.get('create-project').inputSchema.properties;
  assert.equal(createSchema.clientRequestId.maxLength, 128);
  assert.equal(registered.get('get-request').annotations.readOnlyHint, true);
  assert.equal(registered.get('resolve-request').annotations.readOnlyHint, false);
  const area = registered.get('get-area').inputSchema.properties;
  assert.equal(area.limit.default, 20);
  assert.equal(area.limit.maximum, 100);
  assert.equal(area.includeCoordinates.default, false);
  assert.equal(area.includeView.default, false);
  assert.equal(registered.get('get-changes').inputSchema.properties.mode.default, 'compact');
  assert.equal(registered.get('search-architecture').inputSchema.properties.limit.maximum, 100);
  assert(!registered.get('apply-changes').description.includes('from get-architecture'));
  assert(registered.get('apply-changes').description.includes('Trace follows edges only'));
  assert(changeSchema.edges.items.properties.from.description.includes('Upstream'));
  assert(changeSchema.edges.items.properties.to.description.includes('Downstream'));
  assert(registered.get('validate-architecture').description.includes('Run it after writes'));
  assert(!area.projectId.description.includes('from get-architecture'));
  assert(registered.get('list-projects').description.includes('use it directly'));
  const schemaChars = JSON.stringify([...registered.values()], null, 2).length;
  console.log(`Registered tool catalog: ${schemaChars} characters`);
  assert(schemaChars < 17500, `Tool schemas too verbose: ${schemaChars}`);
});

test('registerTool retries only the tools that failed', async () => {
  const h = harness(), calls = new Map();
  h.document.modelContext = {registerTool(tool) {
    calls.set(tool.name, (calls.get(tool.name) || 0) + 1);
    if (tool.name === 'get-outline' && calls.get(tool.name) === 1) throw Error('Not ready');
  }};
  await h.ready();
  await h.tick();
  assert.equal(calls.get('get-outline'), 2);
  assert.equal(calls.get('apply-changes'), 1);
  h.listeners.focus(); await h.drain();
  assert.equal(calls.get('apply-changes'), 1);
});

test('only document.modelContext is used', async () => {
  const h = harness();
  h.navigator.modelContext = {registerTool() {assert.fail('navigator.modelContext must be ignored');},
    provideContext() {assert.fail('provideContext must not be called');}};
  await h.ready();
  for (let i = 0; i < 20; i++) await h.tick();
  assert.equal(JSON.parse(h.window.foldboard.mcpStatus()).available, false);
});

test('registration retry series is bounded and resumes on focus', async () => {
  const h = harness();
  await h.ready();
  for (let i = 0; i < 20; i++) await h.tick();
  assert.equal(h.timers.size, 0);
  let count = 0;
  h.document.modelContext = {registerTool() {count++;}};
  h.listeners.focus(); await h.drain();
  assert.equal(count, 18);
});

test('callback exceptions return a machine code without exposing details', async () => {
  const h = harness(), registered = [];
  h.document.modelContext = {registerTool(tool) {registered.push(tool);}};
  h.window.foldboard.setHandler(() => {throw Error('private internals');});
  await h.drain();
  const result = await registered[0].execute({});
  assert.equal(result.code, 'internal-error');
  assert(!JSON.stringify(result).includes('private'));
});
