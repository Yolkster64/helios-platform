// GlowShader.hlsl - Monado Cyan Glow Effect Shader
// Applies radial gradient bloom effect with customizable intensity

Texture2D inputTexture : register(t0);
SamplerState inputSampler : register(s0);

cbuffer ShaderConstants : register(b0)
{
    float4 glowColor;      // RGBA glow color
    float glowIntensity;   // 0.0 - 1.0
    float blurRadius;      // Pixel radius for blur
    float bloomThreshold;  // Threshold for bloom
};

float4 main(float2 uv : TEXCOORD0) : SV_TARGET
{
    float4 baseColor = inputTexture.Sample(inputSampler, uv);
    
    // Calculate distance from center (0.5, 0.5)
    float2 center = float2(0.5, 0.5);
    float distFromCenter = distance(uv, center);
    
    // Radial gradient for glow
    float radialGradient = 1.0 - saturate(distFromCenter * 2.0);
    
    // Bloom calculation
    float bloomAmount = max(0.0, (length(baseColor.rgb) - bloomThreshold)) * glowIntensity;
    
    // Apply glow
    float4 glowEffect = glowColor * (radialGradient * glowIntensity + bloomAmount);
    
    // Composite result
    float4 result = baseColor + glowEffect;
    result.a = max(baseColor.a, glowEffect.a);
    
    return result;
}
