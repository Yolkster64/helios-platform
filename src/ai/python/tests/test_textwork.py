from helios_agents import textwork


def test_keywords_drops_stopwords_and_ranks_by_count():
    texts = [
        "the routing table reorders the provider chain",
        "provider chain fallback and provider health",
    ]
    result = textwork.keywords(texts, top_n=3)
    tokens = [entry["token"] for entry in result["keywords"]]
    assert tokens[0] == "provider"
    assert "the" not in tokens
    assert "and" not in tokens
    assert result["documents"] == 2


def test_group_similar_groups_near_duplicates():
    texts = [
        "circuit breaker opens after five consecutive failures",
        "the circuit breaker opens after five consecutive failures occur",
        "bicep parameters configure the model deployment capacity",
    ]
    result = textwork.group_similar(texts, threshold=0.5)
    assert result["backend"] in ("sklearn", "jaccard")
    groups = result["groups"]
    assert [0, 1] in groups
    assert [2] in groups


def test_group_similar_keeps_distinct_texts_apart():
    texts = ["alpha beta gamma", "delta epsilon zeta"]
    result = textwork.group_similar(texts, threshold=0.3)
    assert result["groups"] == [[0], [1]]


def test_group_similar_survives_degenerate_tokens():
    result = textwork.group_similar(["a b", "a b c"])
    assert result["groups"] == [[0, 1]]
    assert result["backend"] == "jaccard"


def test_group_similar_is_transitive_across_chains():
    # A~B and B~C but A and C share nothing: single-link puts all three together.
    texts = ["alpha beta", "beta gamma", "gamma delta"]
    result = textwork.group_similar(texts, threshold=0.3)
    assert result["groups"] == [[0, 1, 2]]
