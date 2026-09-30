import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync('ios/Runner/MediaProbe.js', 'utf8');
function fixture(nodes, pageURL = 'https://player.example/embed/sample') {
  const messages = [];
  const events = {};
  let interval;
  let disconnected = false;
  const context = {
    URL, Set, WeakMap, Array, Number,
    document: {
      baseURI: 'https://player.example/embed/sample', documentElement: {},
      querySelectorAll: () => nodes,
      addEventListener: (name, handler) => { events[name] = handler; },
      removeEventListener: name => { delete events[name]; },
    },
    window: {
      location: {href: pageURL},
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
priority.tick();
assert.equal(priority.messages.length, 1, 'Do not promote a secondary player after the main source was seen');
const primaryPending = fixture([node('https://media.example/secondary.mp4'), node('', 'main-video')]);
assert.equal(primaryPending.messages.length, 0, 'Wait for the main player instead of using another video');
const port = fixture([node('https://media.example:8443/file.mp4')]);
assert.equal(port.messages.length, 0, 'The observer must match the native HTTPS port policy');
console.log('Media observer checks passed: delayed source, deduplication, cleanup, URL policy and main-video isolation.');

const autoplay = node('', 'main-video');
autoplay.tagName = 'VIDEO'; autoplay.paused = true;
let plays = 0;
autoplay.play = () => { plays++; return {catch() {}}; };
const cyberdrop = fixture([autoplay], 'https://cyberdrop.cr/e/sample');
assert.equal(plays, 1, 'Cyberdrop starts without a second user tap');
cyberdrop.tick();
assert.equal(plays, 1, 'Do not repeatedly override manual pause/autoplay refusal');
autoplay.currentSrc = 'https://media.example/movie.mp4'; cyberdrop.tick();
assert.equal(plays, 2, 'A source becoming available permits one bounded retry');
autoplay.currentSrc = 'https://media.example/other.mp4'; cyberdrop.tick();
assert.equal(plays, 2, 'Bound autoplay attempts per element');
fixture([autoplay], 'https://cyberdrop.cr.evil.example/e/sample');
fixture([autoplay], 'https://cyberdrop.cr/login');
fixture([autoplay], 'https://other.example/e/sample');
assert.equal(plays, 2, 'Unrelated pages keep their existing gesture policy');
console.log('Cyberdrop autoplay scope, delayed source and bounded retry checks passed.');

const delayed = node('', 'main-video');
delayed.tagName = 'VIDEO'; delayed.paused = true;
let delayedPlays = 0;
delayed.play = () => { delayedPlays++; delayed.paused = false; return {catch() {}}; };
const successful = fixture([delayed], 'https://cyberdrop.cr/e/delayed');
delayed.currentSrc = 'https://media.example/delayed.mp4';
successful.tick();
delayed.paused = true; successful.tick();
assert.equal(delayedPlays, 1, 'A manual pause after successful delayed-source playback must stay paused');
const handoff = node('', 'main-video');
handoff.tagName = 'VIDEO'; handoff.paused = true;
let handoffPlays = 0;
handoff.play = () => { handoffPlays++; handoff.paused = false; return {catch() {}}; };
const native = fixture([handoff], 'https://cyberdrop.cr/e/handoff');
handoff.currentSrc = 'https://media.example/native.mp4';
native.events.forumNativePlayback(); handoff.paused = true;
native.tick();
assert.equal(handoffPlays, 1, 'Native handoff must not restart hidden web playback even before the next source scan');
console.log('Successful playback, manual pause and native handoff autoplay retirement checks passed.');
