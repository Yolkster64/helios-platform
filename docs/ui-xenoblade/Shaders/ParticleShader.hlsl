// ParticleShader.hlsl - Energy Particle Trail Effect
// Renders energy particles with velocity trails and fade-out

struct Particle
{
    float3 position;
    float age;
    float3 velocity;
    float lifetime;
    float4 color;
    float size;
};

Texture2D particleTexture : register(t0);
SamplerState particleSampler : register(s0);

cbuffer ParticleConstants : register(b0)
{
    float4x4 viewProjection;
    float timeElapsed;
    float particleSize;
    float gravity;
    float damping;
};

float4 main(float2 uv : TEXCOORD0, float age : TEXCOORD1) : SV_TARGET
{
    // Sample particle texture
    float4 particleColor = particleTexture.Sample(particleSampler, uv);
    
    // Calculate fade based on age
    float ageRatio = age;
    float fade = 1.0 - saturate(ageRatio);
    
    // Apply glow effect
    float3 glowColor = float3(0.0, 0.83, 1.0); // Cyan
    float4 result = float4(lerp(particleColor.rgb, glowColor, 0.6), particleColor.a * fade);
    
    return result;
}
