import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync('ios/Runner/MediaProbe.js', 'utf8');
function fixture(nodes) {
  const messages = [];
  const events = {};
  let interval;
  let disconnected = false;
  const context = {
    URL, Set, Array, Number,
    document: {
      baseURI: 'https://player.example/embed/sample', documentElement: {},
      querySelectorAll: () => nodes,
      addEventListener: (name, handler) => { events[name] = handler; },
      removeEventListener: name => { delete events[name]; },
    },
    window: {
      webkit: {messageHandlers: {mediaCandidate: {postMessage: value => messages.push(value)}}},
      addEventListener: (name, handler) => { events[name] = handler; },
    },
    MutationObserver: class { observe() {} disconnect() { disconnected = true; } },
    setTimeout: action => { action(); },
    setInterval: action => { interval = action; return 1; },
    clearInterval: () => { interval = null; },
  };
  vm.runInNewContext(source, context);
  return {messages, events, tick: () => interval?.(), disconnected: () => disconnected};
}
const node = (src, id = '', ad = false) => ({currentSrc: src, src, id, closest: () => ad ? {} : null});
const main = node('', 'main-video');
const live = fixture([main]);
assert.equal(live.messages.length, 0);
main.currentSrc = 'https://media.example/stream.mp4?exp=synthetic';
live.events.loadedmetadata();
assert.equal(live.messages.length, 1);
live.tick();
assert.equal(live.messages.length, 1, 'Repeated scans must not repeat the same URL');
main.currentSrc = 'https://media.example/new.mp4';
live.tick();
assert.equal(live.messages.length, 2, 'A new source may be observed after initialization');
live.events.pagehide();
assert.equal(live.disconnected(), true);
const unsafe = fixture([node('blob:https://player.example/id'), node('javascript:bad()'), node('https://user:secret@media.example/file.mp4'), node('https://media.example/ad.mp4', '', true)]);
assert.equal(unsafe.messages.length, 0);
const priority = fixture([node('https://media.example/secondary.mp4'), node('https://media.example/main.mp4', 'main-video')]);
assert.equal(priority.messages[0].url, 'https://media.example/main.mp4');
console.log('Media observer checks passed: delayed source, deduplication, cleanup, unsafe URLs and preferred video.');
