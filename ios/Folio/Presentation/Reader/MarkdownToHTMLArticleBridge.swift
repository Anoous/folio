import Foundation

// MARK: - article.js (inline)

extension MarkdownToHTML {

    /// The JavaScript that powers text-selection highlights, scroll progress
    /// tracking, link interception, and image taps inside the WKWebView reader.
    // swiftlint:disable:next function_body_length
    static let articleJS: String = """
    (function() {
        "use strict";

        var activePopup = null;
        var strings = window.folioStrings || {
            highlight: "Highlight",
            copy: "Copy",
            removeHighlight: "Remove Highlight",
            highlighted: "Highlighted",
            copied: "Copied",
            removedHighlight: "Highlight Removed"
        };

        // ── Swift bridge ─────────────────────────────────────
        function msg(type, data) {
            var payload = Object.assign({type: type}, data || {});
            window.webkit.messageHandlers.folio.postMessage(payload);
        }

        // ── Popup management ─────────────────────────────────
        function closeAllPopups() {
            document.querySelectorAll('.hl-popup').forEach(function(p) { p.remove(); });
            if (activePopup) { activePopup.remove(); activePopup = null; }
        }

        // ── Text offset calculation ──────────────────────────
        function getTextOffset(node, offset) {
            var body = document.querySelector('.article-body');
            if (!body) return 0;
            var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, {
                acceptNode: function(n) {
                    // Skip text inside highlight popups and hidden elements
                    // so that DOM mutations from highlighting don't shift offsets.
                    if (n.parentElement && n.parentElement.closest('.hl-popup')) return NodeFilter.FILTER_REJECT;
                    var style = window.getComputedStyle(n.parentElement);
                    if (style && style.display === 'none') return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            var pos = 0;
            while (walker.nextNode()) {
                if (walker.currentNode === node) return pos + offset;
                pos += walker.currentNode.length;
            }
            return pos;
        }

        // ── Clipboard helper (execCommand fallback) ──────────
        function copyText(text) {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).catch(function() {
                    fallbackCopy(text);
                });
            } else {
                fallbackCopy(text);
            }
        }

        function fallbackCopy(text) {
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.style.position = 'fixed';
            ta.style.left = '-9999px';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
        }

        // ── Create-highlight floating menu ───────────────────
        function showCreateMenu(range) {
            closeAllPopups();
            var rect = range.getBoundingClientRect();
            var menu = document.createElement('div');
            menu.className = 'hl-popup on';
            menu.style.position = 'fixed';
            menu.style.left = (rect.left + rect.width / 2) + 'px';
            menu.style.top = (rect.top - 8) + 'px';
            menu.style.transform = 'translateX(-50%) translateY(-100%)';

            var hlBtn = document.createElement('button');
            hlBtn.className = 'hl-popup-btn';
            hlBtn.textContent = '\\u9AD8\\u4EAE';
            menu.appendChild(hlBtn);

            var cpBtn = document.createElement('button');
            cpBtn.className = 'hl-popup-btn';
            cpBtn.textContent = '\\u590D\\u5236';
            menu.appendChild(cpBtn);

            document.body.appendChild(menu);
            activePopup = menu;

            hlBtn.onclick = function(e) {
                e.stopPropagation();
                var sel = window.getSelection();
                if (sel.rangeCount) {
                    var r = sel.getRangeAt(0);
                    var text = sel.toString();
                    var start = getTextOffset(r.startContainer, r.startOffset);
                    var end = getTextOffset(r.endContainer, r.endOffset);
                    if (text.length > 500) { text = text.substring(0, 500); end = start + 500; }
                    try {
                        var mark = document.createElement('mark');
                        mark.className = 'hl';
                        mark.setAttribute('data-id', 'temp-' + Date.now());
                        r.surroundContents(mark);
                        attachHighlightPopup(mark);
                        sel.removeAllRanges();
                    } catch(ex) {}
                    msg('highlight.create', {text: text, startOffset: start, endOffset: end});
                    msg('toast', {message: '\\u5DF2\\u9AD8\\u4EAE'});
                }
                closeAllPopups();
            };

            cpBtn.onclick = function(e) {
                e.stopPropagation();
                var text = window.getSelection().toString();
                copyText(text);
                msg('toast', {message: '\\u5DF2\\u590D\\u5236'});
                closeAllPopups();
            };
        }

        // ── Attach remove-popup on existing highlight taps ───
        function attachHighlightPopup(mark) {
            mark.onclick = function(e) {
                e.stopPropagation();
                closeAllPopups();
                var popup = document.createElement('div');
                popup.className = 'hl-popup on';

                var rmBtn = document.createElement('button');
                rmBtn.className = 'hl-popup-btn';
                rmBtn.textContent = '\\u79FB\\u9664\\u9AD8\\u4EAE';
                popup.appendChild(rmBtn);

                var cpBtn = document.createElement('button');
                cpBtn.className = 'hl-popup-btn';
                cpBtn.textContent = '\\u590D\\u5236';
                popup.appendChild(cpBtn);

                mark.appendChild(popup);
                activePopup = popup;

                rmBtn.onclick = function(ev) {
                    ev.stopPropagation();
                    var id = mark.getAttribute('data-id');
                    var inner = mark.innerHTML.replace(/<div[^>]*class="hl-popup[^"]*"[^>]*>[\\s\\S]*?<\\/div>/g, '');
                    mark.outerHTML = inner;
                    msg('highlight.remove', {id: id});
                    msg('toast', {message: '\\u5DF2\\u79FB\\u9664\\u9AD8\\u4EAE'});
                };

                cpBtn.onclick = function(ev) {
                    ev.stopPropagation();
                    var text = mark.textContent.trim();
                    copyText(text);
                    msg('toast', {message: '\\u5DF2\\u590D\\u5236'});
                    closeAllPopups();
                };
            };
        }

        // ── Render existing highlights on load ───────────────
        function highlightRange(id, start, end) {
            var body = document.querySelector('.article-body');
            if (!body) return;
            var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
            var pos = 0, startNode = null, startOff = 0, endNode = null, endOff = 0;
            while (walker.nextNode()) {
                var nodeLen = walker.currentNode.length;
                if (!startNode && pos + nodeLen > start) {
                    startNode = walker.currentNode;
                    startOff = start - pos;
                }
                if (pos + nodeLen >= end) {
                    endNode = walker.currentNode;
                    endOff = end - pos;
                    break;
                }
                pos += nodeLen;
            }
            if (startNode && endNode) {
                try {
                    var range = document.createRange();
                    range.setStart(startNode, startOff);
                    range.setEnd(endNode, endOff);
                    var mark = document.createElement('mark');
                    mark.className = 'hl';
                    mark.setAttribute('data-id', id);
                    range.surroundContents(mark);
                    attachHighlightPopup(mark);
                } catch(ex) {}
            }
        }

        function renderExistingHighlights() {
            if (!window.existingHighlights || !window.existingHighlights.length) return;
            var sorted = window.existingHighlights.slice().sort(function(a, b) {
                return b.startOffset - a.startOffset;
            });
            sorted.forEach(function(h) {
                highlightRange(h.id, h.startOffset, h.endOffset);
            });
        }

        // ── Text selection → highlight menu ──────────────────
        document.addEventListener('touchend', function(e) {
            if (!e.target.closest('.article-body')) return;
            setTimeout(function() {
                var sel = window.getSelection();
                if (!sel || sel.isCollapsed || sel.toString().trim().length < 3) return;
                var range = sel.getRangeAt(0);
                var ancestor = range.commonAncestorContainer;
                if (ancestor.closest && ancestor.closest('.hl')) return;
                if (ancestor.parentElement && ancestor.parentElement.closest('.hl')) return;
                showCreateMenu(range);
            }, 200);
        });

        // ── Dismiss popups on background tap ─────────────────
        document.addEventListener('click', function(e) {
            if (!e.target.closest('.hl') && !e.target.closest('.hl-popup')) {
                closeAllPopups();
            }
        });

        function articleBodyMetrics() {
            var body = document.querySelector('.article-body');
            if (!body) {
                return {
                    top: 0,
                    scrollable: Math.max(0, document.body.scrollHeight - window.innerHeight)
                };
            }

            var rect = body.getBoundingClientRect();
            return {
                top: rect.top + window.scrollY,
                scrollable: Math.max(0, body.scrollHeight - window.innerHeight)
            };
        }

        // ── Scroll progress ──────────────────────────────────
        var scrollThrottle = null;
        window.addEventListener('scroll', function() {
            if (scrollThrottle) return;
            scrollThrottle = setTimeout(function() {
                scrollThrottle = null;
                var metrics = articleBodyMetrics();
                var numerator = window.scrollY - metrics.top;
                var pct = metrics.scrollable > 0 ? numerator / metrics.scrollable : 0;
                msg('scroll.progress', {percent: Math.min(1, Math.max(0, pct))});
            }, 100);
        });

        // ── Image tap ────────────────────────────────────────
        document.addEventListener('click', function(e) {
            if (e.target.tagName === 'IMG') {
                msg('image.tap', {src: e.target.src, alt: e.target.alt || ''});
            }
        });

        // ── Link interception ────────────────────────────────
        document.addEventListener('click', function(e) {
            var a = e.target.closest('a');
            if (a && a.href) {
                e.preventDefault();
                msg('link.tap', {href: a.href});
            }
        });

        // ── Called from Swift ─────────────────────────────────
        function scrollToProgress(pct) {
            var clamped = Math.min(1, Math.max(0, pct));
            var metrics = articleBodyMetrics();
            window.scrollTo(0, metrics.top + metrics.scrollable * clamped);
        }

        function setPreferences(fontSize, lineHeight, fontFamily, bgColor, textColor, secondaryColor) {
            var r = document.documentElement.style;
            r.setProperty('--font-size', fontSize + 'px');
            r.setProperty('--line-height', lineHeight);
            r.setProperty('--font-family', fontFamily);
            r.setProperty('--bg', bgColor);
            r.setProperty('--text-1', textColor);
            r.setProperty('--text-2', secondaryColor);
        }

        window.scrollToProgress = scrollToProgress;
        window.setPreferences = setPreferences;
        window.FolioReader = {
            getTextOffset: getTextOffset,
            attachHighlightPopup: attachHighlightPopup,
            scrollToProgress: scrollToProgress,
            setPreferences: setPreferences
        };

        // ── Insight panel toggle ─────────────────────────────
        document.addEventListener('click', function(e) {
            var toggle = e.target.closest('#insight-toggle');
            if (!toggle) return;
            var text = document.getElementById('insight-text');
            var details = document.getElementById('insight-details');
            var chevron = document.getElementById('insight-chevron');
            if (!text) return;
            var expanded = text.classList.toggle('expanded');
            if (details) details.classList.toggle('show', expanded);
            if (chevron) chevron.classList.toggle('expanded', expanded);
        });

        // ── Title scroll visibility ──────────────────────────
        var titleObserver = null;
        function observeTitle() {
            var titleEl = document.getElementById('reader-title');
            if (!titleEl || !window.IntersectionObserver) return;
            titleObserver = new IntersectionObserver(function(entries) {
                entries.forEach(function(entry) {
                    msg('title.visibility', {visible: entry.isIntersecting});
                });
            }, {threshold: 0});
            titleObserver.observe(titleEl);
        }

        // ── Init ─────────────────────────────────────────────
        document.addEventListener('DOMContentLoaded', function() {
            renderExistingHighlights();
            observeTitle();
            msg('content.ready', {height: document.body.scrollHeight});
        });
    })();
    """
}
