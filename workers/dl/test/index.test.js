// Runs without Cloudflare or the network: node --test workers/dl/
// latest.json is stubbed, and the Analytics Engine binding is a recorder.
import { afterEach, beforeEach, test } from 'node:test'
import assert from 'node:assert/strict'
import worker from '../src/index.js'

const realFetch = globalThis.fetch
let latest

beforeEach(() => {
  latest = () => Response.json({ version: '0.9.2', dmgURL: 'https://keelhaven.app/downloads/Keelhaven-0.9.2.dmg' })
  globalThis.fetch = async (url) => {
    assert.equal(String(url), 'https://keelhaven.app/latest.json')
    return latest()
  }
})
afterEach(() => {
  globalThis.fetch = realFetch
})

async function get(path, { method = 'GET', headers = {}, country = 'DE', binding } = {}) {
  const points = []
  const env = { DOWNLOADS: binding ?? { writeDataPoint: (point) => points.push(point) } }
  const request = new Request(`https://dl.keelhaven.app${path}`, { method, headers })
  Object.defineProperty(request, 'cf', { value: country ? { country } : undefined })
  const response = await worker.fetch(request, env)
  return { response, points }
}

const BROWSER = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15'

test('the newest version goes back to the Pages mirror, uncached', async () => {
  const { response } = await get('/Keelhaven-0.9.2.dmg')
  assert.equal(response.status, 302)
  assert.equal(response.headers.get('location'), 'https://keelhaven.app/downloads/Keelhaven-0.9.2.dmg')
  assert.equal(response.headers.get('cache-control'), 'no-store')
})

test('an older version goes to its GitHub release', async () => {
  const { response } = await get('/Keelhaven-0.9.1.dmg')
  assert.equal(response.status, 302)
  assert.equal(response.headers.get('location'),
    'https://github.com/shenxianpeng/keelhaven/releases/download/v0.9.1/Keelhaven-0.9.1.dmg')
})

test('an unreadable latest.json sends even the newest version to its release', async () => {
  for (const broken of [
    () => new Response('nope', { status: 404 }),
    () => new Response('not json'),
    () => Response.json({ version: 92 }),
    () => { throw new TypeError('network down') },
  ]) {
    latest = broken
    const { response } = await get('/Keelhaven-0.9.2.dmg')
    assert.equal(response.headers.get('location'),
      'https://github.com/shenxianpeng/keelhaven/releases/download/v0.9.2/Keelhaven-0.9.2.dmg')
  }
})

test('anything but a versioned DMG is a 404 and counts nothing', async () => {
  for (const path of ['/', '/favicon.ico', '/Keelhaven.dmg', '/Keelhaven-0.9.dmg',
    '/Keelhaven-0.9.2.dmg/', '/downloads/Keelhaven-0.9.2.dmg', '/Keelhaven-0.9.2.zip']) {
    const { response, points } = await get(path)
    assert.equal(response.status, 404, path)
    assert.equal(points.length, 0, path)
  }
})

test('other methods are refused, and a HEAD redirects without counting', async () => {
  const post = await get('/Keelhaven-0.9.2.dmg', { method: 'POST' })
  assert.equal(post.response.status, 405)
  assert.equal(post.response.headers.get('allow'), 'GET, HEAD')
  assert.equal(post.points.length, 0)

  const head = await get('/Keelhaven-0.9.2.dmg', { method: 'HEAD' })
  assert.equal(head.response.status, 302)
  assert.equal(head.points.length, 0)
})

test("a click on the site's button", async () => {
  const { points } = await get('/Keelhaven-0.9.2.dmg?src=site&page=/zh/', {
    headers: { 'user-agent': BROWSER, referer: 'https://keelhaven.app/' },
    country: 'CN',
  })
  assert.deepEqual(points, [{
    indexes: ['0.9.2'],
    blobs: ['site', '0.9.2', 'CN', 'browser', 'keelhaven.app', '/zh/'],
  }])
})

test('without ?src= the source comes from the referrer', async () => {
  const site = await get('/Keelhaven-0.9.2.dmg', { headers: { referer: 'https://www.keelhaven.app/zh/' } })
  assert.deepEqual(site.points[0].blobs.slice(0, 1), ['site'])

  const forum = await get('/Keelhaven-0.9.2.dmg', {
    headers: { 'user-agent': BROWSER, referer: 'https://www.v2ex.com/t/123?p=2#reply' },
  })
  assert.deepEqual(forum.points[0].blobs, ['referral', '0.9.2', 'DE', 'browser', 'www.v2ex.com', '/t/123'])

  const typed = await get('/Keelhaven-0.9.2.dmg', { headers: { referer: 'not a url' }, country: null })
  assert.deepEqual(typed.points[0].blobs, ['direct', '0.9.2', '', 'other', '', ''])
})

test('a tagged link keeps its tag; junk in ?src= or ?page= is ignored', async () => {
  const tagged = await get('/Keelhaven-0.9.2.dmg?src=v2ex')
  assert.equal(tagged.points[0].blobs[0], 'v2ex')

  const junk = await get(`/Keelhaven-0.9.2.dmg?src=${'x'.repeat(40)}&page=javascript:alert(1)`, {
    headers: { referer: 'https://keelhaven.app/' },
  })
  assert.deepEqual(junk.points[0].blobs.slice(0, 1), ['site'])
  assert.equal(junk.points[0].blobs[5], '/')
})

test('the user agent is reduced to a client class', async () => {
  const classes = {
    'curl/8.7.1': 'curl',
    'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)': 'bot',
    'Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)': 'bot',
    [BROWSER]: 'browser',
    'Wget/1.24.5': 'other',
  }
  for (const [ua, client] of Object.entries(classes)) {
    const { points } = await get('/Keelhaven-0.9.2.dmg', { headers: { 'user-agent': ua } })
    assert.equal(points[0].blobs[3], client, ua)
  }
})

test('a failing or missing binding still serves the download', async () => {
  for (const binding of [{ writeDataPoint() { throw new Error('quota') } }, {}]) {
    const { response } = await get('/Keelhaven-0.9.2.dmg', { binding })
    assert.equal(response.status, 302)
  }
})
