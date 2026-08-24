#!/usr/bin/env python3
"""PROTOTYPE, throwaway. Pulls one real day of candidates for judge calibration.

Simulates the daily run for DAY: arXiv submittedDate window + Crossref created-date delta,
using the queries settled in research/fetch-contracts.md. Writes candidates.json.
"""
import html, json, re, sys, urllib.parse, urllib.request
import xml.etree.ElementTree as ET

DAY = sys.argv[1] if len(sys.argv) > 1 else "2026-08-21"
Y, M, D = DAY.split("-")
UA = "research-tape-prototype/0.1 (https://github.com/neoyipeng2018/research-tape; mailto:yipeng.n@gmail.com)"

FIN = ["financial", "finance", "stock market", "portfolio", "asset pricing",
       "credit risk", "volatility", "algorithmic trading", "limit order book",
       "market microstructure"]

def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=60).read()

def clean(s):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(s or ""))).strip()

# --- arXiv -------------------------------------------------------------------
terms = "+OR+".join('abs:%22' + t.replace(" ", "+") + '%22' for t in FIN)
q = (f"%28cat:q-fin.*+OR+%28%28cat:cs.CE+OR+cat:cs.LG+OR+cat:cs.AI%29+AND+%28{terms}%29%29%29"
     f"+AND+submittedDate:[{Y}{M}{D}0000+TO+{Y}{M}{D}2359]")
xml = get(f"https://export.arxiv.org/api/query?search_query={q}&max_results=200")
NS = {"a": "http://www.w3.org/2005/Atom"}
cands = []
for e in ET.fromstring(xml).findall("a:entry", NS):
    aid = e.find("a:id", NS).text.rsplit("/", 1)[1]
    cands.append({
        "key": aid.rsplit("v", 1)[0], "source": "arXiv",
        "title": clean(e.find("a:title", NS).text),
        "abstract": clean(e.find("a:summary", NS).text),
        "link": f"https://arxiv.org/abs/{aid}",
    })

# --- Crossref ----------------------------------------------------------------
AI_RE = re.compile(r"\b(artificial intelligence|machine learning|deep learning|neural network|"
                   r"llm|large language model|transformer|reinforcement learning|generative ai|ai)\b", re.I)
FIN_RE = re.compile(r"\b(financ\w*|bank\w*|stock\w*|portfolio|asset pricing|credit risk|"
                    r"volatilit\w*|trading|market\w*|investment\w*|monetary|hedge|derivative\w*)\b", re.I)
sel = "DOI,title,abstract,resource,created,type"
url = ("https://api.crossref.org/prefixes/10.2139/works?"
       f"filter=from-created-date:{DAY},until-created-date:{DAY}&rows=1000&cursor=*"
       f"&select={sel}&mailto=yipeng.n@gmail.com")
seen_ssrn, cursor = 0, "*"
while True:
    r = json.loads(get(url.replace("cursor=*", "cursor=" + urllib.parse.quote(cursor))))["message"]
    items = r["items"]
    if not items:
        break
    seen_ssrn += len(items)
    for it in items:
        title = clean(" ".join(it.get("title") or []))
        abstract = clean(it.get("abstract", ""))
        if not (FIN_RE.search(title) and AI_RE.search(title + " " + abstract)):
            continue
        cands.append({
            "key": it["DOI"], "source": "SSRN", "title": title, "abstract": abstract,
            "link": (it.get("resource", {}).get("primary", {}) or {}).get("URL", "https://doi.org/" + it["DOI"]),
        })
    cursor = r.get("next-cursor")
    if not cursor or len(items) < 1000:
        break

for i, c in enumerate(cands, 1):
    c["id"] = i
json.dump({"day": DAY, "ssrn_scanned": seen_ssrn, "candidates": cands},
          open("prototype/candidates.json", "w"), indent=1)
print(f"{DAY}: arXiv={sum(1 for c in cands if c['source']=='arXiv')} "
      f"SSRN={sum(1 for c in cands if c['source']=='SSRN')}/{seen_ssrn} scanned  total={len(cands)}")
