/*
 * SwipeNav.js — iOS-12-safe horizontal swipe -> Lovelace view navigation.
 *
 * Injected into the kiosk WKWebView at document start. Re-implements the
 * behavior of the zanna-37 "Swipe navigation" card in plain ES5 so it runs on
 * the iPad Mini 2's iOS 12.5.8 WebKit (which can't parse the card's optional
 * chaining / nullish coalescing — the card is a hard SyntaxError there, in both
 * the kiosk app and Safari).
 *
 * Guard is global so a re-injected copy never double-binds. Listeners are on
 * `document` (capture) so they keep working across HA SPA view changes without
 * re-binding. Horizontal swipes left/right advance the current view; vertical
 * swipes are left to the page so scrolling still works. Deliberately short on
 * features versus the real card — no animation, no per-tab skipping, no wrap
 * toggle (always wraps).
 */
(function () {
  "use strict";

  if (window.__kioskSwipeNav) {
    return;
  }
  window.__kioskSwipeNav = true;

  // DEBUG instrumentation -> relayed to the app via the existing `kiosk` message
  // bridge where KioskViewController logs anything with type "swipeDiag".
  // Remove alongside the ObjC dependency before shipping this as final.
  function report(data) {
    try {
      if (window.webkit && window.webkit.messageHandlers &&
          window.webkit.messageHandlers.kiosk) {
        var msg = {};
        for (var k in data) {
          if (data.hasOwnProperty(k)) {
            msg[k] = data[k];
          }
        }
        msg.type = "swipeDiag";
        window.webkit.messageHandlers.kiosk.postMessage(msg);
      }
    } catch (err) { /* never let diagnostics break swiping */ }
  }

  function describePanel() {
    var panel = getPanel();
    if (!panel) {
      return "no panel";
    }
    var views = panel.lovelace && panel.lovelace.config ?
        (panel.lovelace.config.views || []) : [];
    var route = panel.route ? (panel.route.prefix || "") : "";
    var vw = 0, vh = 0;
    var appLayout = document.querySelector("ha-app-layout") ||
        document.querySelector("home-assistant") || document.body;
    var cs = window.getComputedStyle(appLayout);
    if (cs) {
      vw = cs.overflowY ? cs.overflowY : "";
      vh = appLayout.clientHeight;
      // unwrap the real scroll container for Lovelace views
      var view = document.querySelector("hui-view") ||
          document.querySelector("ha-panel-lovelace");
      if (view) {
        var vcs = window.getComputedStyle(view);
        vh = view.clientHeight;
        cs = vcs;
      }
    }
    return "views=" + views.length +
        " routePrefix=" + route +
        " panel=" + (panel.tagName || "") +
        " appLayoutOverflowY=" + (cs ? cs.overflowY : "?") +
        " scrollH=" + (cs ? cs.overflowY === "auto" || cs.overflowY === "scroll" : false) +
        " viewClientH=" + vh;
  }

  // DEBUG: dump the DOM shape so we can see what the page actually renders.
  // Prior round showed home-assistant + action-handler only, and nothing else —
  // which is HA's authorize/onboarding shell, not a rendered Lovelace dashboard.
  // To tell between "dashboard hidden in home-assistant's shadow root" and "we
  // are on the OAuth authorize screen", walk INTO shadow roots (several levels)
  // and list the custom-element tags found, plus report the injected token length
  // so we can see whether the webview even has an auth token.
  function shadowWalk(root, depth, seen, names) {
    if (!root || depth > 4) {
      return;
    }
    var kids = root.children || [];
    for (var i = 0; i < kids.length; i++) {
      var el = kids[i];
      var tag = (el.tagName || "").toLowerCase();
      if (tag.indexOf("-") !== -1 && !seen[tag]) {
        seen[tag] = true;
        names.push(tag + (el.is ? "[is=" + el.is + "]" : "") +
            (el.shadowRoot ? ">shadow" : ""));
      }
      if (el.shadowRoot) {
        shadowWalk(el.shadowRoot, depth + 1, seen, names);
      }
    }
  }

  // DEBUG: If the dashboard renders visually but no view/card elements are in
  // the top document's (shadow) tree, the Lovelace UI is probably inside an
  // IFRAME (HA is same-origin here, so we can reach into it). Report iframes and
  // check each same-origin frame for ha-panel-lovelace / hui-view / hui-card.
  function probeFrame(w) {
    var out = null;
    try {
      var d = w.document;
      var panel = d.querySelector && d.querySelector("ha-panel-lovelace");
      var view = d.querySelector && d.querySelector("hui-view");
      var card = d.querySelector && d.querySelector("ha-card");
      var els = d.querySelectorAll ? d.querySelectorAll("*").length : -1;
      out = "host=" + (w === window ? "top" : "iframe") +
          " url=" + w.location.href +
          " #els=" + els +
          " panel=" + (panel ? "y" : "n") +
          " view=" + (view ? "y" : "n") +
          " haCard=" + (card ? "y" : "n");
    } catch (e) {
      out = "iframe unreachable cross-origin";
    }
    return out;
  }

  function describeDom() {
    var seen = {};
    var names = [];
    if (document.body) { shadowWalk(document.body, 0, seen, names); }
    var ha = document.querySelector("home-assistant");
    if (ha && ha.shadowRoot) { shadowWalk(ha.shadowRoot, 0, seen, names); }
    var tok = window._kioskToken;
    var frames = [];
    for (var f = 0; f < window.frames.length; f++) {
      frames.push(probeFrame(window.frames[f]));
    }
    var iframes = document.querySelectorAll("iframe");
    var frameSrcs = [];
    for (var i = 0; i < iframes.length; i++) {
      frameSrcs.push(iframes[i].getAttribute("src") || "(nosrc)");
    }
    return "href=" + window.location.href +
        " ready=" + document.readyState +
        " tokenLen=" + (tok ? String(tok).length : "none") +
        " nIframes=" + iframes.length +
        " iframeSrc=" + frameSrcs.join(" | ") +
        " topFrame=" + probeFrame(window) +
        " frames=" + (frames.length ? frames.join(" ; ") : "none") +
        " custom=" + names.join(",");
  }

  report({ event: "injected", desc: (function () {
    var panel = getPanel();
    return "docReadyState=" + document.readyState +
        " hasPanel=" + (panel ? "yes" : "no") +
        " winW=" + window.innerWidth;
  })() });

  // Minimum drag as a fraction of screen width before a swipe counts.
  var MIN_FRAC = 0.15;

  var x0 = null;
  var y0 = null;

  // Elements that legitimately need horizontal drags; swipes started on these
  // (or any of their ancestors) are ignored so we don't fight sliders, maps,
  // carousels, or scrollbars.
  var blockedNodeNames = [
    "ha-map-card",
    "swipe-card",
    "ha-slider",
    "paper-slider",
    "input",
  ];

  function isBlockedElement(el) {
    var name = el.nodeName ? el.nodeName.toLowerCase() : "";
    if (blockedNodeNames.indexOf(name) !== -1) {
      return true;
    }
    if (el.classList && el.classList.contains("ha-scrollbar")) {
      return true;
    }
    return false;
  }

  function pathContainsBlocked(e) {
    var path = e.composedPath ? e.composedPath() : null;
    if (!path) {
      return false;
    }
    for (var i = 0; i < path.length; i++) {
      var el = path[i];
      if (!el || el === window || el === document) {
        continue;
      }
      if (el.nodeType === 1 && isBlockedElement(el)) {
        return true;
      }
    }
    return false;
  }

  // The entire Lovelace UI renders inside nested shadow roots of the
  // <home-assistant> element, so a plain document.querySelector can never find
  // ha-panel-lovelace / hui-view — it only sees light DOM. Diagnostic rounds
  // confirmed: user sees a working dashboard, but no iframes and an almost-empty
  // light DOM (#els=48, only ha-drawer/ha-snowflakes/action-handler visible at
  // depth 4), i.e. everything real is buried in shadow roots. Search those.
  function deepFind(sel) {
    var direct = document.querySelector(sel);
    if (direct) {
      return direct;
    }
    var stack = [];
    var all = document.querySelectorAll("*");
    for (var i = 0; i < all.length; i++) {
      if (all[i].shadowRoot) {
        stack.push(all[i].shadowRoot);
      }
    }
    var guard = 0;
    while (stack.length && guard < 50000) {
      var sr = stack.pop();
      guard++;
      var found = sr.querySelector ? sr.querySelector(sel) : null;
      if (found) {
        return found;
      }
      var kids = sr.querySelectorAll ? sr.querySelectorAll("*") : [];
      for (var j = 0; j < kids.length; j++) {
        if (kids[j].shadowRoot) {
          stack.push(kids[j].shadowRoot);
        }
      }
    }
    return null;
  }

  function getPanel() {
    return deepFind("ha-panel-lovelace");
  }

  function getViews() {
    var panel = getPanel();
    if (!panel || !panel.lovelace || !panel.lovelace.config) {
      return null;
    }
    return panel.lovelace.config.views;
  }

  function currentViewIndex() {
    var path = window.location.pathname.replace(/\/+$/, "");
    var seg = (path.split("/").pop() || "").trim();
    if (seg === "") {
      return 0;
    }
    if (/^\d+$/.test(seg)) {
      return parseInt(seg, 10);
    }
    var views = getViews();
    if (!views) {
      return null;
    }
    for (var i = 0; i < views.length; i++) {
      var vPath = views[i].path;
      if (vPath === undefined || vPath === null || vPath.trim() === "") {
        if (String(i) === seg) {
          return i;
        }
      } else if (vPath === seg) {
        return i;
      }
    }
    return null;
  }

  // Navigation lock: HA re-renders the whole view on this low-memory iPad, which
  // is slow. Rapid swipes queue several re-renders that pile up and feel laggier.
  // Drop any swipe that lands while a navigation is still settling (cooldown),
  // instead of stacking more expensive renders on top of it.
  var navBusy = false;
  var NAV_LOCK_MS = 1200;

  function navigate(direction) {
    if (navBusy) {
      return;
    }
    var views = getViews();
    var current = currentViewIndex();
    if (!views || current === null || views.length < 2) {
      report({ event: "navNoop", why: "views/current invalid",
               viewsLen: views ? views.length : -1, current: current,
               dom: describeDom() });
      return;
    }
    var next = current + direction;
    if (next < 0) {
      next = views.length - 1;
    }
    if (next >= views.length) {
      next = 0;
    }

    var panel = getPanel();
    var prefix = "lovelace";
    if (panel && panel.route && panel.route.prefix) {
      prefix = panel.route.prefix.replace(/^\/+|\/+$/g, "") || prefix;
    }

    var target = views[next].path;
    if (target === undefined || target === null || target.trim() === "") {
      target = String(next);
    }

    var url = "/" + prefix + "/" + target +
              window.location.search + window.location.hash;

    if (url !== window.location.pathname +
               window.location.search + window.location.hash) {
      report({ event: "navFire", dir: direction, curIdx: current,
               nextIdx: next, prefix: prefix, target: target,
               url: url, pathname: window.location.pathname,
               desc: describePanel() });
      navBusy = true;
      setTimeout(function () {
        navBusy = false;
      }, NAV_LOCK_MS);
      window.history.pushState(null, "", url);
      window.dispatchEvent(new CustomEvent("location-changed"));
    } else {
      report({ event: "navSameUrl", url: url });
    }
  }

  function onStart(e) {
    if (e.touches && e.touches.length > 1) {
      x0 = null;
      y0 = null;
      return; // two-finger gesture (pinch/zoom) — not a swipe
    }
    if (pathContainsBlocked(e)) {
      x0 = null;
      y0 = null;
      return;
    }
    x0 = e.touches && e.touches[0] ? e.touches[0].clientX : e.clientX;
    y0 = e.touches && e.touches[0] ? e.touches[0].clientY : e.clientY;
  }

  function onMove(e) {
    if (x0 === null || y0 === null) {
      return;
    }
    if (e.touches && e.touches.length > 1) {
      x0 = null;
      y0 = null;
      return; // became a two-finger gesture mid-drag
    }
    var t = e.touches && e.touches[0];
    if (!t) {
      return;
    }
    var dx = t.clientX - x0;
    var dy = t.clientY - y0;
    // Stop iOS from taking over the horizontal drag so the touch can complete.
    if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > 8) {
      e.preventDefault();
    }
  }

  function onEnd(e) {
    if (x0 === null || y0 === null) {
      return;
    }
    var t = e.changedTouches && e.changedTouches[0];
    var dx = t ? t.clientX - x0 : 0;
    var dy = t ? t.clientY - y0 : 0;
    x0 = null;
    y0 = null;

    if (Math.abs(dy) > Math.abs(dx) ||
        Math.abs(dx) < window.innerWidth * MIN_FRAC) {
      return; // vertical (let page scroll) or too short — ignore
    }
    navigate(dx < 0 ? 1 : -1);
  }

  document.addEventListener("touchstart", onStart, {
    capture: true,
    passive: true,
  });
  document.addEventListener("touchmove", onMove, {
    capture: true,
    passive: false,
  });
  document.addEventListener("touchend", onEnd, {
    capture: true,
    passive: true,
  });
})();
