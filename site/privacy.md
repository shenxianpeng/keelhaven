# Privacy

Keelhaven is built so that there is nothing to have a policy about.

- **No account.** There is nothing to sign up for and no identity attached to
  your use of the app.
- **No telemetry.** The app does not phone home — no analytics, no crash
  reporting, no usage statistics.
- **No server of ours.** Your backups travel directly from your Mac to the
  destination you configured — a local drive, your NAS, or your own
  S3-compatible bucket. Keelhaven operates no server that could see them.
- **Encrypted before it leaves.** Everything is encrypted on your Mac before a
  single byte is uploaded. The repository password stays in your macOS Keychain
  and is never sent anywhere.

That covers the app, which is the part that touches your files. Three things
around it are worth stating plainly:

- **This website** is a static site served by GitHub Pages; GitHub sees the
  requests it serves, as any web host does. It uses Google Analytics for basic
  visit statistics — the only third party the pages load, and it applies to
  the website only, never the app.
- **The Download button** goes through `dl.keelhaven.app`, a small Cloudflare
  Worker of ours that counts the download and sends you on to the same file.
  Cloudflare sees that one request, as any host would; what we keep from it
  is the version, your country, the page or site the link was on, and whether
  a browser, `curl` or a bot asked — never your IP address.
- **Support email** sent to our address is routed through Cloudflare Email
  Routing to a mailbox we read. We see your address and whatever you write, and
  use it only to answer you.

Questions? See the [FAQ](/#faq) or email us — the address is in the site
footer.
