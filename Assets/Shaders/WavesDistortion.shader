Shader "Custom/WavesDistortion"
{
    Properties
    {
        [Header(Main)]
        _Color ("Color", Color) = (1,1,1,1)
        _Glossiness("Smoothness", Range(0,1)) = 0.5
        _Metallic("Metallic", Range(0,1)) = 0.0

        [Header(Waves)]
        _WaveA("Wave A (dir, steepness, wavelength)", Vector) = (1, 0, 0.5, 10)
        _WaveB("Wave B (dir, steepness, wavelength)", Vector) = (0, 1, 0.25, 20)
        _WaveC("Wave C (dir, steepness, wavelength)", Vector) = (1, 1, 0.15, 10)
        _WaveD("Wave D (dir, steepness, wavelength)", Vector) = (1, 1, 0.5, 10)

        [Header(Fog)]
        _WaterFogColor("Water Fog Color", Color) = (0, 0, 0, 0)
        _WaterFogDensity("Water Fog Density", Range(0, 2)) = 0.1

        [Header(Reflection)]
        _CubeMap("Cube Map", CUBE) = "white" {}
        _ReflectionStrength("Reflection Strength", Range(0, 1)) = 1

        [Header(Refraction)]
        _RefractionStrength("Refraction Strength", Range(0, 1)) = 0.25
        _RefractionStrength2("Refraction Strength2", Range(0, 1)) = 0.25

        [Header(Distortion)]
        _MainTex("Albedo (RGB)", 2D) = "white" {}
        [NoScaleOffset] _FlowMap("Flow (RG, A noise)", 2D) = "black" {}
        [NoScaleOffset] _DerivHeightMap("Deriv (AG) Height (B)", 2D) = "black" {}
        _UJump("U jump per phase", Range(-0.25, 0.25)) = 0.25
        _VJump("V jump per phase", Range(-0.25, 0.25)) = 0.25
        _Tiling("Tiling", Float) = 1
        _Speed("Speed", Float) = 1
        _FlowStrength("Flow Strength", Float) = 1
        _FlowOffset("Flow Offset", Float) = 0
        _HeightScale("Height Scale, Constant", Float) = 0.25
        _HeightScaleModulated("Height Scale, Modulated", Float) = 0.75
    }
        SubShader
        {
            Tags { "RenderType" = "Transparent" "Queue" = "Transparent"}
            LOD 200
            CULL OFF

            GrabPass { "_WaterBackground" }
            CGPROGRAM
            // Physically based Standard lighting model, and enable shadows on all light types
            #pragma surface surf Standard alpha finalcolor:ResetAlpha vertex:vert addshadow

            // Use shader model 3.0 target, to get nicer looking lighting
            #pragma target 3.0

            #include "Flow.cginc"
            #include "LookingThroughWater.cginc"

        samplerCUBE _CubeMap;
        sampler2D _MainTex, _FlowMap, _DerivHeightMap;
        float _UJump, _VJump, _Tiling, _Speed, _FlowStrength, _FlowOffset, _HeightScale, _HeightScaleModulated;
        float _ReflectionStrength;
        float4 _WaveA, _WaveB, _WaveC, _WaveD;

        struct Input
        {
            float2 uv_MainTex;
            float4 screenPos;
            float3 viewDir;
            float3 worldRefl;
            INTERNAL_DATA
        };

        half _Glossiness;
        half _Metallic;
        fixed4 _Color;

        float3 GerstnerWave(float4 wave, float3 p, inout float3 tangent, inout float3 binormal) {
            float2 dir = wave.xy;
            float steepness = wave.z;
            float wavelength = wave.w;

            float k = 2 * UNITY_PI / wavelength;
            float a = steepness / k;
            float c = sqrt(9.8 / k);
            float2 d = normalize(dir);
            float f = k * (dot(d, p.xz) - c * _Time.y);

            tangent += float3(
                - d.x * d.x * (steepness * sin(f)),
                d.x * (steepness * cos(f)),
                -d.x * d.y * (steepness * sin(f)));
            binormal += float3(
                -d.x * d.y * (steepness * sin(f)),
                d.y * (steepness * cos(f)),
                - d.y * d.y * (steepness * sin(f)));

            return float3(
                d.x * (a * cos(f)),
                a * sin(f),
                d.y * (a * cos(f)));
        }

        void ResetAlpha(Input IN, SurfaceOutputStandard o, inout fixed4 color) {
            color.a = 1;
        }

        float3 UnpackDerivativeHeight(float4 textureData) {
            float3 dh = textureData.agb;
            dh.xy = dh.xy * 2 - 1;
            return dh;
        }
        
        void vert(inout appdata_full vertexData) {
            float3 p = vertexData.vertex.xyz;
            float3 tangent = float3(1, 0, 0);
            float3 binormal = float3(0, 0, 1);

            p += GerstnerWave(_WaveA, vertexData.vertex.xyz, tangent, binormal);
            p += GerstnerWave(_WaveB, vertexData.vertex.xyz, tangent, binormal);
            p += GerstnerWave(_WaveC, vertexData.vertex.xyz, tangent, binormal);
            p += GerstnerWave(_WaveD, vertexData.vertex.xyz, tangent, binormal);

            float3 normal = normalize(cross(binormal, tangent));

            vertexData.vertex.xyz = p;
            vertexData.normal = normal;
        }

        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            float3 flow = tex2D(_FlowMap, IN.uv_MainTex).rgb;
            flow.xy = flow.xy * 2 - 1;
            flow *= _FlowStrength;
            float noise = tex2D(_FlowMap, IN.uv_MainTex).a;
            float time = _Time.y * _Speed + noise;
            float2 jump = float2(_UJump, _VJump);

            float3 uvwA = FlowUVW(IN.uv_MainTex, flow.xy, jump, _FlowOffset, _Tiling, time, false);
            float3 uvwB = FlowUVW(IN.uv_MainTex, flow.xy, jump, _FlowOffset, _Tiling, time, true);

            float finalHeightScale = length(flow.z) * _HeightScaleModulated + _HeightScale;

            float3 dhA = UnpackDerivativeHeight(tex2D(_DerivHeightMap, uvwA.xy)) * (uvwA.z * finalHeightScale);
            float3 dhB = UnpackDerivativeHeight(tex2D(_DerivHeightMap, uvwB.xy)) * (uvwB.z * finalHeightScale);
            o.Normal = normalize(float3(-(dhA.xy + dhB.xy), 1));

            fixed4 texA = tex2D(_MainTex, uvwA.xy) * uvwA.z;
            fixed4 texB = tex2D(_MainTex, uvwB.xy) * uvwB.z;
            fixed4 c = (texA + texB) * _Color;
            o.Albedo = c.rgb;
            // Metallic and smoothness come from slider variables
            o.Metallic = _Metallic;
            o.Smoothness = _Glossiness;
            o.Alpha = c.a;

            o.Emission = ColorBelowWater(IN.screenPos, o.Normal * 20) * (1 - c.a)
                + texCUBE(_CubeMap, WorldReflectionVector(IN, o.Normal)).rgb * (1 - dot(IN.viewDir, o.Normal)) * (1 - _ReflectionStrength);
        }
        ENDCG
    }
    FallBack "Diffuse"
}
