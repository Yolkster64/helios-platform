"""Text analysis for agent outputs: keywords and near-duplicate grouping.

scikit-learn (TF-IDF cosine) is used when installed; otherwise Jaccard token
overlap keeps the results useful on a bare interpreter.
"""

from __future__ import annotations

import re
from collections import Counter

try:
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.metrics.pairwise import cosine_similarity
    _HAVE_SKLEARN = True
except ImportError:  # pragma: no cover - exercised on bare interpreters
    _HAVE_SKLEARN = False

_TOKEN = re.compile(r"[a-z0-9_]{2,}")
_STOPWORDS = frozenset(
    "the a an and or but of to in for on with as is are was were be been being "
    "this that these those it its at by from not no do does did done have has "
    "had will would can could should may might must if then else when while "
    "you your we our they their i me my he she his her them us".split()
)


def _tokens(text: str) -> list[str]:
    return [t for t in _TOKEN.findall(text.lower()) if t not in _STOPWORDS]


def keywords(texts: list[str], top_n: int = 10) -> dict:
    """Most frequent meaningful tokens across the corpus."""
    counts = Counter(token for text in texts for token in _tokens(text))
    return {
        "keywords": [
            {"token": token, "count": count}
            for token, count in counts.most_common(max(1, top_n))
        ],
        "documents": len(texts),
    }


def _jaccard(a: set[str], b: set[str]) -> float:
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def _similarity_matrix(texts: list[str]) -> tuple[list[list[float]], str]:
    if _HAVE_SKLEARN and len(texts) > 1:
        try:
            matrix = TfidfVectorizer(token_pattern=_TOKEN.pattern).fit_transform(
                [t.lower() for t in texts])
            return cosine_similarity(matrix).tolist(), "sklearn"
        except ValueError:
            pass  # empty vocabulary (no token >= 2 chars) — fall back to Jaccard
    token_sets = [set(_tokens(t)) for t in texts]
    return [[_jaccard(a, b) for b in token_sets] for a in token_sets], "jaccard"


def group_similar(texts: list[str], threshold: float = 0.6) -> dict:
    """Group near-duplicate texts by greedy single-link over the similarity matrix.

    Mirrors the C++ spoke's compare-dedup idea, but across arbitrary agent
    outputs rather than one fan-out's responses.
    """
    sim, backend = _similarity_matrix(texts)
    group_of: list[int | None] = [None] * len(texts)
    groups: list[list[int]] = []
    for i in range(len(texts)):
        if group_of[i] is not None:
            continue
        # Single-link means transitive closure: expand through newly added members
        # (A~B and B~C puts C with A even when A and C aren't directly similar),
        # not just through the seed.
        members = [i]
        group_of[i] = len(groups)
        frontier = [i]
        while frontier:
            a = frontier.pop()
            for j in range(len(texts)):
                if group_of[j] is None and sim[a][j] >= threshold:
                    group_of[j] = len(groups)
                    members.append(j)
                    frontier.append(j)
        members.sort()
        groups.append(members)
    return {
        "groups": groups,
        "backend": backend,
    }
