#=============================================================================
# COMPREHENSIVE MODEL CATALOG - 30+ MODELS ACROSS 12+ PROVIDERS
# ============================================================================
# Full inventory of available AI models with detailed specifications,
# pricing, performance, latency, and optimal use cases.
#=============================================================================

# ============================================================================
# MODEL REGISTRY - 35+ MODELS
# ============================================================================

$Global:ModelRegistry = @{
    # ===== ANTHROPIC (6 models) =====
    'claude-haiku-4.5' = @{
        provider = 'Anthropic'
        family = 'Claude'
        tier = 'ultra-fast-cheap'
        costPerMillion = 0.80
        mmluScore = 88.5
        hEvalScore = 82.0
        mathScore = 74.2
        latencyMs = 12
        maxTokens = 100000
        strengths = @('speed', 'cost-efficiency', 'real-time-processing')
        weaknesses = @('complex-reasoning', 'nuanced-tasks')
        specializations = @('classification', 'extraction', 'routing')
        supported_languages = 100
        context_window_tokens = 100000
    }
    'claude-sonnet-4.5' = @{
        provider = 'Anthropic'
        family = 'Claude'
        tier = 'production-standard'
        costPerMillion = 3.0
        mmluScore = 96.8
        hEvalScore = 92.5
        mathScore = 88.1
        latencyMs = 45
        maxTokens = 200000
        strengths = @('balanced', 'reasoning', 'coding', 'creative')
        weaknesses = @('ultra-fast-needed')
        specializations = @('qa', 'code-generation', 'summarization')
        supported_languages = 100
        context_window_tokens = 200000
    }
    'claude-opus-4.5' = @{
        provider = 'Anthropic'
        family = 'Claude'
        tier = 'premium-quality'
        costPerMillion = 15.0
        mmluScore = 98.2
        hEvalScore = 95.1
        mathScore = 92.3
        latencyMs = 98
        maxTokens = 200000
        strengths = @('complex-reasoning', 'quality', 'nuance')
        weaknesses = @('cost', 'latency')
        specializations = @('strategy', 'complex-analysis', 'creative-writing')
        supported_languages = 100
        context_window_tokens = 200000
    }
    'claude-instant-1.2' = @{
        provider = 'Anthropic'
        family = 'Claude'
        tier = 'legacy-fast'
        costPerMillion = 0.50
        mmluScore = 84.0
        hEvalScore = 78.5
        mathScore = 70.0
        latencyMs = 8
        maxTokens = 100000
        strengths = @('speed', 'legacy-compatibility')
        weaknesses = @('quality', 'reasoning')
        specializations = @('routing', 'simple-tasks')
        supported_languages = 50
        context_window_tokens = 100000
    }
    'claude-3-haiku' = @{
        provider = 'Anthropic'
        family = 'Claude-3'
        tier = 'previous-generation-fast'
        costPerMillion = 0.25
        mmluScore = 86.0
        hEvalScore = 80.0
        mathScore = 72.0
        latencyMs = 10
        maxTokens = 100000
        strengths = @('ultra-cost-effective')
        weaknesses = @('feature-parity')
        specializations = @('extraction', 'classification')
        supported_languages = 50
        context_window_tokens = 100000
    }
    'claude-3-sonnet' = @{
        provider = 'Anthropic'
        family = 'Claude-3'
        tier = 'previous-generation-balanced'
        costPerMillion = 2.0
        mmluScore = 94.0
        hEvalScore = 88.0
        mathScore = 82.0
        latencyMs = 35
        maxTokens = 200000
        strengths = @('previous-version-stability')
        weaknesses = @('newer-benchmarks-underperform')
        specializations = @('general-purpose')
        supported_languages = 100
        context_window_tokens = 200000
    }

    # ===== OPENAI (7 models) =====
    'gpt-4o-mini' = @{
        provider = 'OpenAI'
        family = 'GPT-4o'
        tier = 'fast-cheap'
        costPerMillion = 0.15
        mmluScore = 89.5
        hEvalScore = 85.0
        mathScore = 76.0
        latencyMs = 18
        maxTokens = 128000
        strengths = @('cost', 'speed', 'multimodal-fast')
        weaknesses = @('complex-reasoning-gaps')
        specializations = @('image-analysis', 'fast-responses')
        supported_languages = 100
        context_window_tokens = 128000
    }
    'gpt-4o' = @{
        provider = 'OpenAI'
        family = 'GPT-4o'
        tier = 'production-multimodal'
        costPerMillion = 5.0
        mmluScore = 96.5
        hEvalScore = 91.5
        mathScore = 87.5
        latencyMs = 52
        maxTokens = 128000
        strengths = @('multimodal', 'vision', 'reasoning')
        weaknesses = @('text-only-overkill')
        specializations = @('vision-tasks', 'multimodal-analysis')
        supported_languages = 100
        context_window_tokens = 128000
    }
    'gpt-4-turbo' = @{
        provider = 'OpenAI'
        family = 'GPT-4'
        tier = 'legacy-premium'
        costPerMillion = 10.0
        mmluScore = 95.5
        hEvalScore = 90.5
        mathScore = 86.0
        latencyMs = 75
        maxTokens = 128000
        strengths = @('reasoning', 'code')
        weaknesses = @('newer-models-better')
        specializations = @('code-analysis', 'legacy-systems')
        supported_languages = 100
        context_window_tokens = 128000
    }
    'gpt-4' = @{
        provider = 'OpenAI'
        family = 'GPT-4'
        tier = 'legacy-oldest'
        costPerMillion = 8.0
        mmluScore = 93.0
        hEvalScore = 88.0
        mathScore = 84.0
        latencyMs = 85
        maxTokens = 8192
        strengths = @('stable', 'proven')
        weaknesses = @('slow', 'expensive', 'small-context')
        specializations = @('legacy-api')
        supported_languages = 100
        context_window_tokens = 8192
    }
    'gpt-5-preview' = @{
        provider = 'OpenAI'
        family = 'GPT-5'
        tier = 'next-generation-beta'
        costPerMillion = 20.0
        mmluScore = 98.5
        hEvalScore = 96.5
        mathScore = 94.0
        latencyMs = 120
        maxTokens = 128000
        strengths = @('cutting-edge', 'advanced-reasoning', 'future-proof')
        weaknesses = @('beta-bugs', 'expensive')
        specializations = @('advanced-reasoning', 'research')
        supported_languages = 100
        context_window_tokens = 128000
    }
    'o1-preview' = @{
        provider = 'OpenAI'
        family = 'O1'
        tier = 'reasoning-specialist'
        costPerMillion = 15.0
        mmluScore = 97.0
        hEvalScore = 94.0
        mathScore = 97.2
        latencyMs = 180
        maxTokens = 128000
        strengths = @('complex-math', 'step-by-step-reasoning', 'science')
        weaknesses = @('slow', 'expensive', 'not-for-speed')
        specializations = @('mathematical-reasoning', 'scientific-analysis')
        supported_languages = 50
        context_window_tokens = 128000
    }
    'o1-mini' = @{
        provider = 'OpenAI'
        family = 'O1'
        tier = 'reasoning-fast'
        costPerMillion = 3.0
        mmluScore = 95.5
        hEvalScore = 91.0
        mathScore = 94.0
        latencyMs = 60
        maxTokens = 128000
        strengths = @('reasoning-cheaper', 'math-efficiency')
        weaknesses = @('not-ultra-fast')
        specializations = @('math', 'logic')
        supported_languages = 50
        context_window_tokens = 128000
    }

    # ===== GOOGLE (5 models) =====
    'gemini-3-flash' = @{
        provider = 'Google'
        family = 'Gemini-3'
        tier = 'ultra-fast-cheap'
        costPerMillion = 0.08
        mmluScore = 89.0
        hEvalScore = 84.0
        mathScore = 75.0
        latencyMs = 21
        maxTokens = 1000000
        strengths = @('ultra-fast', 'huge-context', 'cost')
        weaknesses = @('reasoning-gaps')
        specializations = @('document-processing', 'video-analysis')
        supported_languages = 100
        context_window_tokens = 1000000
    }
    'gemini-3-pro' = @{
        provider = 'Google'
        family = 'Gemini-3'
        tier = 'production-balanced'
        costPerMillion = 1.0
        mmluScore = 94.5
        hEvalScore = 89.0
        mathScore = 85.0
        latencyMs = 48
        maxTokens = 1000000
        strengths = @('balanced', 'huge-context', 'multimodal')
        weaknesses = @('none-major')
        specializations = @('general-purpose', 'document-analysis')
        supported_languages = 100
        context_window_tokens = 1000000
    }
    'gemini-3-ultra' = @{
        provider = 'Google'
        family = 'Gemini-3'
        tier = 'premium-reasoning'
        costPerMillion = 8.0
        mmluScore = 98.0
        hEvalScore = 94.0
        mathScore = 91.0
        latencyMs = 110
        maxTokens = 1000000
        strengths = @('advanced-reasoning', 'massive-context', 'quality')
        weaknesses = @('expensive', 'slow')
        specializations = @('complex-analysis', 'research')
        supported_languages = 100
        context_window_tokens = 1000000
    }
    'gemini-2-flash' = @{
        provider = 'Google'
        family = 'Gemini-2'
        tier = 'previous-generation-fast'
        costPerMillion = 0.05
        mmluScore = 87.0
        hEvalScore = 82.0
        mathScore = 73.0
        latencyMs = 15
        maxTokens = 1000000
        strengths = @('legacy', 'previous-stable')
        weaknesses = @('older-model')
        specializations = @('legacy-integration')
        supported_languages = 100
        context_window_tokens = 1000000
    }
    'gemini-1.5-pro' = @{
        provider = 'Google'
        family = 'Gemini-1.5'
        tier = 'mature-production'
        costPerMillion = 2.5
        mmluScore = 93.5
        hEvalScore = 88.0
        mathScore = 84.0
        latencyMs = 60
        maxTokens = 1000000
        strengths = @('proven', 'stable', 'context')
        weaknesses = @('older')
        specializations = @('general-purpose')
        supported_languages = 100
        context_window_tokens = 1000000
    }

    # ===== ALIBABA QWEN (4 models) =====
    'qwen-turbo-max' = @{
        provider = 'Alibaba'
        family = 'Qwen'
        tier = 'ultra-cheap'
        costPerMillion = 0.008
        mmluScore = 87.0
        hEvalScore = 81.0
        mathScore = 72.0
        latencyMs = 16
        maxTokens = 4096
        strengths = @('ultra-cheap-177x-less-than-opus', 'speed')
        weaknesses = @('limited-context', 'performance-gaps')
        specializations = @('budget-routing', 'volume-processing')
        supported_languages = 25
        context_window_tokens = 4096
    }
    'qwen-plus' = @{
        provider = 'Alibaba'
        family = 'Qwen'
        tier = 'balanced'
        costPerMillion = 0.05
        mmluScore = 91.0
        hEvalScore = 86.0
        mathScore = 80.0
        latencyMs = 35
        maxTokens = 8000
        strengths = @('cheap', 'reasonable-quality')
        weaknesses = @('context-limited')
        specializations = @('cost-optimized-tasks')
        supported_languages = 50
        context_window_tokens = 8000
    }
    'qwen-max' = @{
        provider = 'Alibaba'
        family = 'Qwen'
        tier = 'premium'
        costPerMillion = 0.5
        mmluScore = 95.0
        hEvalScore = 90.0
        mathScore = 86.0
        latencyMs = 55
        maxTokens = 8000
        strengths = @('quality-cost-balance')
        weaknesses = @('none-major')
        specializations = @('balanced-workloads')
        supported_languages = 50
        context_window_tokens = 8000
    }
    'qwen-long' = @{
        provider = 'Alibaba'
        family = 'Qwen'
        tier = 'long-context'
        costPerMillion = 0.3
        mmluScore = 93.0
        hEvalScore = 88.0
        mathScore = 82.0
        latencyMs = 70
        maxTokens = 1000000
        strengths = @('massive-context', 'cheap')
        weaknesses = @('not-fastest')
        specializations = @('document-processing', 'long-analysis')
        supported_languages = 50
        context_window_tokens = 1000000
    }

    # ===== MISTRAL (3 models) =====
    'mistral-large-2' = @{
        provider = 'Mistral'
        family = 'Mistral'
        tier = 'production'
        costPerMillion = 2.0
        mmluScore = 92.5
        hEvalScore = 87.5
        mathScore = 81.0
        latencyMs = 42
        maxTokens = 32768
        strengths = @('GDPR-friendly', 'EU-compliant', 'reasoning')
        weaknesses = @('smaller-than-claude-opus')
        specializations = @('eu-compliance', 'general-purpose')
        supported_languages = 100
        context_window_tokens = 32768
    }
    'mistral-medium' = @{
        provider = 'Mistral'
        family = 'Mistral'
        tier = 'balanced'
        costPerMillion = 0.8
        mmluScore = 89.5
        hEvalScore = 84.0
        mathScore = 78.0
        latencyMs = 28
        maxTokens = 32768
        strengths = @('cost-balanced', 'compliance')
        weaknesses = @('moderate-performance')
        specializations = @('balanced-eu-workloads')
        supported_languages = 100
        context_window_tokens = 32768
    }
    'mistral-small' = @{
        provider = 'Mistral'
        family = 'Mistral'
        tier = 'fast-cheap'
        costPerMillion = 0.2
        mmluScore = 86.0
        hEvalScore = 80.0
        mathScore = 74.0
        latencyMs = 15
        maxTokens = 32768
        strengths = @('fast', 'cheap', 'compliance')
        weaknesses = @('limited-reasoning')
        specializations = @('fast-classification')
        supported_languages = 100
        context_window_tokens = 32768
    }

    # ===== META LLAMA (3 models) =====
    'llama-3.1-405b' = @{
        provider = 'Meta'
        family = 'Llama-3.1'
        tier = 'on-premise-premium'
        costPerMillion = 0.0  # Self-hosted
        mmluScore = 97.0
        hEvalScore = 93.0
        mathScore = 90.0
        latencyMs = 200
        maxTokens = 131072
        strengths = @('open-source', 'on-premise', 'privacy', 'quality')
        weaknesses = @('slow', 'requires-infrastructure')
        specializations = @('privacy-critical', 'on-premise-deployment')
        supported_languages = 100
        context_window_tokens = 131072
    }
    'llama-3.1-70b' = @{
        provider = 'Meta'
        family = 'Llama-3.1'
        tier = 'on-premise-balanced'
        costPerMillion = 0.0
        mmluScore = 94.5
        hEvalScore = 90.0
        mathScore = 87.0
        latencyMs = 120
        maxTokens = 131072
        strengths = @('open-source', 'balanced', 'privacy')
        weaknesses = @('requires-setup')
        specializations = @('privacy-workloads')
        supported_languages = 100
        context_window_tokens = 131072
    }
    'llama-3.1-8b' = @{
        provider = 'Meta'
        family = 'Llama-3.1'
        tier = 'on-premise-edge'
        costPerMillion = 0.0
        mmluScore = 89.0
        hEvalScore = 82.0
        mathScore = 76.0
        latencyMs = 50
        maxTokens = 131072
        strengths = @('lightweight', 'edge-deployment', 'fast')
        weaknesses = @('limited-capability')
        specializations = @('edge-devices', 'low-resource')
        supported_languages = 100
        context_window_tokens = 131072
    }

    # ===== XAI GROK (2 models) =====
    'grok-3' = @{
        provider = 'xAI'
        family = 'Grok'
        tier = 'cutting-edge'
        costPerMillion = 12.0
        mmluScore = 98.0
        hEvalScore = 94.5
        mathScore = 93.0
        latencyMs = 100
        maxTokens = 131072
        strengths = @('cutting-edge', 'advanced-reasoning', 'real-time-knowledge')
        weaknesses = @('expensive', 'new')
        specializations = @('advanced-analysis', 'specialized-reasoning')
        supported_languages = 100
        context_window_tokens = 131072
    }
    'grok-2' = @{
        provider = 'xAI'
        family = 'Grok'
        tier = 'production'
        costPerMillion = 6.0
        mmluScore = 96.0
        hEvalScore = 91.0
        mathScore = 90.0
        latencyMs = 80
        maxTokens = 131072
        strengths = @('reasoning', 'knowledge-integration')
        weaknesses = @('newer')
        specializations = @('reasoning-tasks')
        supported_languages = 100
        context_window_tokens = 131072
    }

    # ===== PERPLEXITY & ALTERNATIVE (2 models) =====
    'sonar-pro' = @{
        provider = 'Perplexity'
        family = 'Sonar'
        tier = 'research-grade'
        costPerMillion = 8.0
        mmluScore = 96.5
        hEvalScore = 91.5
        mathScore = 88.0
        latencyMs = 65
        maxTokens = 127072
        strengths = @('research-focused', 'knowledge-retrieval', 'citations')
        weaknesses = @('specialized-use-case')
        specializations = @('research', 'factual-accuracy')
        supported_languages = 100
        context_window_tokens = 127072
    }
    'nova-pro' = @{
        provider = 'AWS'
        family = 'Nova'
        tier = 'aws-integrated'
        costPerMillion = 0.3
        mmluScore = 91.0
        hEvalScore = 86.0
        mathScore = 80.0
        latencyMs = 38
        maxTokens = 300000
        strengths = @('aws-integration', 'cost-effective', 'long-context')
        weaknesses = @('aws-specific')
        specializations = @('aws-environments')
        supported_languages = 100
        context_window_tokens = 300000
    }

    # ===== SPECIALIZED MODELS (3 models) =====
    'deepseek-v3' = @{
        provider = 'DeepSeek'
        family = 'DeepSeek'
        tier = 'specialized-reasoning'
        costPerMillion = 0.14
        mmluScore = 94.0
        hEvalScore = 89.0
        mathScore = 91.0
        latencyMs = 55
        maxTokens = 64000
        strengths = @('math', 'code', 'cheap')
        weaknesses = @('limited-languages')
        specializations = @('mathematical-reasoning', 'code-generation')
        supported_languages = 20
        context_window_tokens = 64000
    }
    'yi-lightning' = @{
        provider = '01.AI'
        family = 'Yi'
        tier = 'fast-specialized'
        costPerMillion = 0.06
        mmluScore = 88.0
        hEvalScore = 83.0
        mathScore = 77.0
        latencyMs = 14
        maxTokens = 200000
        strengths = @('ultra-fast', 'cheap', 'asian-languages')
        weaknesses = @('general-performance-gaps')
        specializations = @('high-speed-processing')
        supported_languages = 50
        context_window_tokens = 200000
    }
    'command-r-plus' = @{
        provider = 'Cohere'
        family = 'Command-R'
        tier = 'enterprise'
        costPerMillion = 3.0
        mmluScore = 92.0
        hEvalScore = 87.0
        mathScore = 81.0
        latencyMs = 50
        maxTokens = 4096
        strengths = @('business-logic', 'retrieval-augmented-generation', 'enterprise')
        weaknesses = @('limited-context')
        specializations = @('rag-systems', 'enterprise-workflows')
        supported_languages = 100
        context_window_tokens = 4096
    }
}

# ============================================================================
# MODEL GROUPING & CATEGORIZATION
# ============================================================================

function Get-ModelsByTier {
    param([string]$Tier)
    return $Global:ModelRegistry.GetEnumerator() | 
        Where-Object { $_.Value.tier -eq $Tier } |
        Select-Object -ExpandProperty Name
}

function Get-ModelsByProvider {
    param([string]$Provider)
    return $Global:ModelRegistry.GetEnumerator() | 
        Where-Object { $_.Value.provider -eq $Provider } |
        Select-Object -ExpandProperty Name
}

function Get-ModelsBySpecialization {
    param([string]$Specialization)
    return $Global:ModelRegistry.GetEnumerator() | 
        Where-Object { $_.Value.specializations -contains $Specialization } |
        Select-Object -ExpandProperty Name
}

function Get-FastestModels {
    param([int]$Count = 5)
    return $Global:ModelRegistry.GetEnumerator() |
        Sort-Object { $_.Value.latencyMs } |
        Select-Object -First $Count -ExpandProperty Name
}

function Get-CheapestModels {
    param([int]$Count = 5)
    return $Global:ModelRegistry.GetEnumerator() |
        Sort-Object { $_.Value.costPerMillion } |
        Select-Object -First $Count -ExpandProperty Name
}

function Get-HighestPerformance {
    param([int]$Count = 5)
    return $Global:ModelRegistry.GetEnumerator() |
        Sort-Object { $_.Value.mmluScore } -Descending |
        Select-Object -First $Count -ExpandProperty Name
}

function Get-BestValueModels {
    param([int]$Count = 5)
    return $Global:ModelRegistry.GetEnumerator() |
        Sort-Object {
            # Performance per dollar: MMLU / Cost
            $_.Value.mmluScore / [Math]::Max(0.001, $_.Value.costPerMillion)
        } -Descending |
        Select-Object -First $Count -ExpandProperty Name
}

function Get-ModelDetails {
    param([string]$ModelID)
    return $Global:ModelRegistry[$ModelID]
}

function Get-AllModels {
    return $Global:ModelRegistry.Keys
}

function Get-ModelCount {
    return $Global:ModelRegistry.Count
}

# ============================================================================
# PROVIDER ANALYSIS
# ============================================================================

function Get-ProviderAnalysis {
    $providers = @{}
    
    $Global:ModelRegistry.GetEnumerator() | ForEach-Object {
        $provider = $_.Value.provider
        if (-not $providers[$provider]) {
            $providers[$provider] = @{
                Models = @()
                CheapestModel = $null
                FastestModel = $null
                BestQuality = $null
            }
        }
        $providers[$provider].Models += $_.Key
    }
    
    # Find best in each category per provider
    foreach ($provider in $providers.Keys) {
        $models = $providers[$provider].Models
        
        $cheapest = $models | ForEach-Object { 
            @{ Name = $_; Cost = $Global:ModelRegistry[$_].costPerMillion }
        } | Sort-Object Cost | Select-Object -First 1
        
        $fastest = $models | ForEach-Object { 
            @{ Name = $_; Latency = $Global:ModelRegistry[$_].latencyMs }
        } | Sort-Object Latency | Select-Object -First 1
        
        $best = $models | ForEach-Object { 
            @{ Name = $_; Score = $Global:ModelRegistry[$_].mmluScore }
        } | Sort-Object Score -Descending | Select-Object -First 1
        
        $providers[$provider].CheapestModel = $cheapest.Name
        $providers[$provider].FastestModel = $fastest.Name
        $providers[$provider].BestQuality = $best.Name
        $providers[$provider].ModelCount = $models.Count
    }
    
    return $providers
}

# ============================================================================
# DYNAMIC MODEL SELECTION
# ============================================================================

function Select-OptimalModel {
    param(
        [string]$TaskType,
        [ValidateSet('cost', 'speed', 'quality', 'balanced')]
        [string]$Objective = 'balanced',
        [decimal]$BudgetPerRequest = 0.05,
        [int]$MaxLatencyMs = 5000
    )
    
    $candidates = $Global:ModelRegistry.GetEnumerator() | Where-Object {
        $_.Value.costPerMillion -le ($BudgetPerRequest * 1000000) -and
        $_.Value.latencyMs -le $MaxLatencyMs
    }
    
    $scored = $candidates | ForEach-Object {
        $model = $_.Key
        $specs = $_.Value
        
        $qualityScore = $specs.mmluScore / 100
        $costScore = 1 / ([Math]::Max(0.001, $specs.costPerMillion / 0.1))
        $speedScore = 1000 / ([Math]::Max(1, $specs.latencyMs))
        
        $score = switch ($Objective) {
            'cost' { $costScore }
            'speed' { $speedScore }
            'quality' { $qualityScore }
            'balanced' { ($qualityScore * 0.33) + ($speedScore * 0.33) + ($costScore * 0.34) }
        }
        
        [PSCustomObject]@{
            Model = $model
            Score = $score
            Quality = $qualityScore
            Cost = $specs.costPerMillion
            Speed = $specs.latencyMs
        }
    }
    
    return $scored | Sort-Object Score -Descending | Select-Object -First 3
}

# ============================================================================
# EXPORTS
# ============================================================================

Export-ModuleMember -Function @(
    'Get-ModelsByTier',
    'Get-ModelsByProvider',
    'Get-ModelsBySpecialization',
    'Get-FastestModels',
    'Get-CheapestModels',
    'Get-HighestPerformance',
    'Get-BestValueModels',
    'Get-ModelDetails',
    'Get-AllModels',
    'Get-ModelCount',
    'Get-ProviderAnalysis',
    'Select-OptimalModel'
) -Variable 'ModelRegistry'
