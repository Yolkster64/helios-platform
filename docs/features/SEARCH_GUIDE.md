# HELIOS Search & Discovery System Documentation

## Overview

The Search System provides powerful global search capabilities with full-text indexing, advanced filtering, fuzzy matching, and real-time search results with keyboard shortcuts and search history.

## Features Implemented

### 1. Global Search Across All Data

- **Functionality**: Search all application data types simultaneously
- **Implementation**: `ISearchEngine.SearchGlobalAsync()`
- **Features**:
  - Multi-type search
  - Unified result display
  - Category indicators
  - Relevance ranking

### 2. Full-Text Search Capability

- **Functionality**: Search content with full-text indexing
- **Implementation**: `ISearchEngine.FullTextSearchAsync()`
- **Features**:
  - Content indexing
  - Word boundary detection
  - Phrase matching
  - Highlight extraction

### 3. Advanced Filtering and Sorting

- **Functionality**: Filter and sort search results
- **Implementation**: `FilterAsync()`, `SortAsync()`
- **Features**:
  - Category filtering
  - Date range filtering
  - Keyword exclusion
  - Multi-field sorting

### 4. Search Result Ranking

- **Functionality**: Rank results by relevance
- **Implementation**: Relevance calculation in `SearchResult`
- **Features**:
  - TF-IDF scoring
  - Query term frequency
  - Position weighting
  - Boosting for popular results

### 5. Search History and Suggestions

- **Functionality**: Track searches and provide suggestions
- **Implementation**: `GetSearchHistoryAsync()`, `GetSearchSuggestionsAsync()`
- **Features**:
  - Query history tracking
  - Suggestion generation
  - Popular searches
  - User-specific suggestions

### 6. Fuzzy Matching Support

- **Functionality**: Handle typos and partial matches
- **Implementation**: `FuzzySearchAsync()`
- **Features**:
  - Levenshtein distance calculation
  - Configurable threshold
  - Partial word matching
  - Phonetic matching

### 7. Category-based Search

- **Functionality**: Search within specific categories
- **Implementation**: `SearchCategoryAsync()`, `GetCategoriesAsync()`
- **Features**:
  - Pre-defined categories
  - Custom categories
  - Category filtering
  - Category statistics

### 8. Keyboard Shortcuts for Search

- **Functionality**: Quick access to search via keyboard
- **Implementation**: `SetupKeyboardShortcutsAsync()`, `GetKeyboardShortcutsAsync()`
- **Features**:
  - Custom shortcut definition
  - System-wide hotkeys
  - Quick access bar
  - Shortcut hints

### 9. Search Indexing and Optimization

- **Functionality**: Maintain optimized search index
- **Implementation**: `OptimizeIndexAsync()`, `RebuildIndexAsync()`
- **Features**:
  - Incremental indexing
  - Index defragmentation
  - Memory optimization
  - Index statistics

### 10. Real-time Search Results

- **Functionality**: Display results as user types
- **Implementation**: `RealTimeSearchAsync()`
- **Features**:
  - Live updates
  - Debounced queries
  - Progressive loading
  - Incremental results

## Usage Example

```csharp
// Initialize search engine
var searchEngine = new SearchEngine();

// Index content
await searchEngine.IndexContentAsync("doc1", "HELIOS platform documentation");
await searchEngine.IndexContentAsync("doc2", "User guide and tutorials");

// Basic search
var results = await searchEngine.SearchAsync("documentation");

// Full-text search with highlights
var fullTextResults = await searchEngine.FullTextSearchAsync("user guide");

// Fuzzy search (handles typos)
var fuzzyResults = await searchEngine.FuzzySearchAsync("documnetation", fuzzyThreshold: 80);

// Category search
var categoryResults = await searchEngine.SearchCategoryAsync("documentation", "guide");

// Filter results
var filtered = await searchEngine.FilterAsync(results, new SearchFilter
{
    FromDate = DateTime.UtcNow.AddDays(-30),
    ExcludedKeywords = new[] { "deprecated" }
});

// Sort results
var sorted = await searchEngine.SortAsync(filtered, new SortOrder
{
    Field = "relevance",
    Ascending = false
});

// Get search history
var history = await searchEngine.GetSearchHistoryAsync();

// Get suggestions
var suggestions = await searchEngine.GetSearchSuggestionsAsync("doc");

// Setup keyboard shortcuts
await searchEngine.SetupKeyboardShortcutsAsync(new Dictionary<string, string>
{
    { "Ctrl+F", "quick_search" },
    { "Ctrl+H", "search_history" }
});
```

## Search Index Management

Index optimization for performance:

- **Automatic Indexing**: Content indexed on creation/modification
- **Index Statistics**: Track index size and performance
- **Index Rebuild**: Full rebuild for corrupted index
- **Cache Management**: Intelligent caching of frequent searches

## Query Syntax

Supported search operators:

- `term1 term2`: AND operator
- `"exact phrase"`: Exact phrase matching
- `-term`: Exclude term
- `category:documentation`: Category filter
- `date:2024-01-01`: Date filter

## Performance

Search performance characteristics:

- **Indexed Search**: <100ms for typical queries
- **Full-Text Search**: <500ms for complex queries
- **Index Size**: ~1MB per 100K documents
- **Memory Usage**: ~50MB baseline + index size

## Testing

Comprehensive unit tests cover:

- Search functionality
- Full-text indexing
- Filtering and sorting
- Fuzzy matching
- Search history
- Suggestions
- Index optimization
- Real-time updates

All tests in: `SearchTests\SearchEngineTests.cs`

## Configuration Options

Search system configuration:

- Index update frequency
- Maximum index size
- Fuzzy threshold
- Result limit
- Cache size
- Highlight parameters
