#!/usr/bin/env python3
"""Generate bounded Pinterest search plans without fetching Pinterest pages."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from urllib.parse import urlencode


GENERAL_MODIFIERS = [
    ("editorial high end", "polished references", ["quality", "editorial"]),
    ("designer award winning", "designer references", ["quality", "designer"]),
    ("2026 contemporary", "current visual language", ["current", "2026"]),
    ("materials lighting details", "material and lighting study", ["detail"]),
    ("unexpected creative direction", "less obvious alternatives", ["creative"]),
    ("natural daylight", "daylight and atmosphere", ["lighting", "daylight"]),
    ("calm refined composition", "clean composition", ["composition"]),
    ("premium material palette", "material palette", ["materials"]),
    ("professional photo no collage", "single photographic view", ["photography"]),
    ("clean styling", "reduced visual clutter", ["composition", "clean"]),
]

INTERIOR_MODIFIERS = [
    ("wide angle full room", "complete spatial composition", ["interior", "full-space"]),
    ("realistic interior photography", "photographic realism", ["interior", "realistic"]),
    ("architectural photography", "architectural composition", ["interior", "architecture"]),
    ("完整空间 广角 实景", "Chinese full-space expansion", ["zh", "full-space"]),
    ("室内设计 实景摄影", "Chinese realism expansion", ["zh", "realistic"]),
]

ZH_MODIFIERS = [
    ("高级感", "Chinese quality expansion", ["zh", "quality"]),
    ("设计灵感", "Chinese inspiration expansion", ["zh", "inspiration"]),
    ("材质细节", "Chinese detail expansion", ["zh", "detail"]),
]


@dataclass(frozen=True)
class SearchIdea:
    priority: int
    query: str
    url: str
    intent: str
    style_tags: list[str]
    notes: str


def pinterest_url(query: str) -> str:
    return "https://www.pinterest.com/search/pins/?" + urlencode({"q": query})


def normalize_brief(brief: str) -> str:
    return " ".join(brief.replace("\n", " ").split()).strip()


def build_queries(
    brief: str, lang: str, count: int, *, interior: bool = False
) -> list[SearchIdea]:
    base = normalize_brief(brief)
    if not base:
        raise ValueError("Brief cannot be empty.")

    limit = max(1, min(count, 16))
    candidates: list[tuple[str, str, list[str]]] = [
        ("", "baseline search", ["baseline"])
    ]
    if interior:
        candidates.extend(INTERIOR_MODIFIERS)
    candidates.extend(GENERAL_MODIFIERS)
    if lang in {"zh", "both"}:
        candidates.extend(ZH_MODIFIERS)

    ideas: list[SearchIdea] = []
    seen: set[str] = set()
    for modifier, intent, tags in candidates:
        query = f"{base} {modifier}".strip()
        key = query.casefold()
        if key in seen:
            continue
        seen.add(key)
        ideas.append(
            SearchIdea(
                priority=len(ideas) + 1,
                query=query,
                url=pinterest_url(query),
                intent=intent,
                style_tags=tags,
                notes="Use one focused search, then refine only when visible results miss the brief.",
            )
        )
        if len(ideas) >= limit:
            break
    return ideas


def render_markdown(ideas: list[SearchIdea]) -> str:
    lines = ["## Pinterest Search Plan", ""]
    for idea in ideas:
        lines.append(f"{idea.priority}. [{idea.query}]({idea.url})")
        lines.append(f"   Intent: {idea.intent}")
        lines.append(f"   Tags: {', '.join(idea.style_tags)}")
        lines.append("")
    return "\n".join(lines).rstrip()


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Pinterest search URLs.")
    parser.add_argument("brief", help="Creative or design brief.")
    parser.add_argument("--lang", choices=["en", "zh", "both"], default="both")
    parser.add_argument("--count", type=int, default=12)
    parser.add_argument("--interior", action="store_true")
    parser.add_argument("--format", choices=["markdown", "json"], default="markdown")
    args = parser.parse_args()

    ideas = build_queries(args.brief, args.lang, args.count, interior=args.interior)
    if args.format == "json":
        print(json.dumps([asdict(idea) for idea in ideas], ensure_ascii=False, indent=2))
    else:
        print(render_markdown(ideas))


if __name__ == "__main__":
    main()
