# Privacy

**Your browser shouldn't be watching you.**

Firn is a calm browser for the Mac, and privacy is part of that calm. There's no account to make, no analytics, and no Firn server. What you do in Firn stays on your Mac.

This page explains exactly what Firn keeps, what it sends, and to whom, in plain words. Firn is open source, so you don't have to take our word for any of it: every line is on [GitHub](https://github.com/dwurgy/firn).

---

## No account, no tracking, no telemetry

Firn doesn't ask who you are. It doesn't count how often you open it, which buttons you press, or which sites you visit, and it doesn't report crashes or "usage statistics" anywhere. There's no Firn server for any of that to go to.

## Every space is its own browser

Most browsers keep one pile of cookies and sign-ins and let everything share it. In Firn, each space is truly separate.

Work and Personal each have their own:

- sign-ins and cookies
- site data, like what a site saves to remember you
- history and recently closed tabs
- Basecamp, groups, and tabs

Signing into Gmail in Work doesn't sign you into Personal. A shopping site you visit in Personal can't see what you did in Work. The command bar and address suggestions only ever show the space you're in.

**Sharing is your choice.** When you make a new space, you can keep it separate (the default) or have it share sign-ins with one other space. A shared space says so plainly, and you can stop sharing at any time. It then starts fresh, signed out of everything.

**Deleting a space deletes its data.** Its tabs, cookies, sign-ins, and site data are erased from your Mac. If another space shares them, they stay until that space is gone too.

## Ads and trackers, blocked

Firn blocks ads and trackers from the moment you open it, using the public EasyList and EasyPrivacy lists. The lists are built into the app, so blocking never has to phone home to work.

If a site breaks, open it and choose **Stop Blocking on** that site in the View menu. That only changes the one site, in the one space.

## What Firn sends, and to whom

Besides the websites you visit, Firn makes only these requests on its own.

**Site icons.** To show a site's icon in your sidebar, Firn asks that same site for it, without its cookies or your sign-ins, so the request can't be tied to you. The welcome fetches the suggested sites' icons the same way.

**Scam checks.** Firn uses macOS's own Safe Browsing service, the same one Safari uses. It keeps a list of known scam sites on your Mac. When a page might be on that list, it asks Apple using a short code calculated from the address, never the address itself. If the site is a known scam, you'll see a warning instead of the page.

**Search suggestions, only if you turn them on.** They're off by default. If you turn them on, your search engine sees what you type in the address bar as you type it, without your cookies or sign-ins. Your searches themselves go to the search engine you choose: Google by default, or Bing, DuckDuckGo, or Ecosia in Settings.

**Nothing else.** No analytics, no update checks yet, and no Firn server.

## What stays on your Mac

Your tabs, spaces, Basecamp, groups, and settings are saved on your Mac so they come back when you reopen Firn. Each space's cookies, sign-ins, and site data are kept on your Mac, separately for each space.

All of it lives in Firn's own sandbox folder (`~/Library/Containers/`), where other apps can't reach it. None of it is uploaded anywhere.

Firn's own logs never record the addresses you visit.

**Tabs that tidy themselves away** are deleted for good 30 days after they're tidied, or as soon as you close them. Firn remembers your last 30 closed tabs so you can bring one back with ⇧⌘T.

## Camera and microphone

A site can only use your camera or microphone after it asks and you click **Allow**. Firn shows which site is asking, and if it's a part of another page, which page it's on. **Don't Allow** is always the default. Only secure (https) sites can ask at all, and a yes lasts only while that tab is open.

## Built to keep your data in

Firn runs in Apple's App Sandbox, which walls it off from the rest of your Mac. It can only touch what it's given:

- the internet, to load web pages
- files you pick yourself, in an Open or Save window
- your Downloads folder, for downloads
- your camera and microphone, only after you allow a site
- printing
- macOS's Safe Browsing service, for scam warnings

Nothing else on your Mac is open to it. Every web page is treated as untrusted, and Firn's own helpers inside pages run walled off from the page itself, so a site can't reach into Firn.

## What Firn can't promise

The sites you visit can still see you visit them, like they would in any browser. Firn blocks the trackers it knows about, but no list catches everything. And when you sign in to a site, that site knows it's you. Firn keeps those sign-ins in their own space; it can't make a site forget you.

If Firn ever needs to send something new, like checking for updates, this page will say so first, in plain words.

## Questions

Firn is open source under the Mozilla Public License 2.0. You can read the code, or ask a question, on [GitHub](https://github.com/dwurgy/firn).
