Shader "Custom/Caustics"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0

        [Header(Caustics)]
        _CausticsTex("Caustics (RGB)", 2D) = "white" {}
        _Caustics_ST1("Caustics Tiling XY, Offset XY", Vector) = (1,1,0,0)
        _Caustics_ST2("Caustics Tiling XY, Offset XY", Vector) = (1,1,0,0)
        _Speed1("Speed1", Vector) = (1,1,0,0)
        _Speed2("Speed2", Vector) = (1,1,0,0)
        _SplitRGB("SplitRGB", Float) = 10
        _MaxHeight("Maximum Height", Float) = 10
        _Intensity("Intensity", Float) = 3
    }
    SubShader
    {
        Tags { "RenderType"="Opaque"}
        LOD 200

        CGPROGRAM
        // Physically based Standard lighting model, and enable shadows on all light types
        #pragma surface surf Standard fullforwardshadows

        // Use shader model 3.0 target, to get nicer looking lighting
        #pragma target 3.0
        //_MainTex is for object texture, _CausticsTex is for caustics texture 
        sampler2D _MainTex, _CausticsTex;
        // We will sample twice same texture for more realistic caustics movement
        float4 _Caustics_ST1, _Caustics_ST2;
        float2 _Speed1, _Speed2;
        // Different wavelengths of light diffract differently when passing through a medium. 
        // We will split RGB components to get that effect.
        // _MaxHeight is there to limit caustics not to go above water and _Intensity provides strength of the output color
        float _SplitRGB, _MaxHeight, _Intensity;

        struct Input
        {
            float2 uv_MainTex;
            float3 worldPos;
            float4 screenPos;
        };

        half _Glossiness;
        half _Metallic;
        fixed4 _Color;

        float3 caustics(float2 uvTex) {
            // ------------ First caustics sampling ----------------
            fixed2 uv = uvTex * _Caustics_ST1.xy + _Caustics_ST1.zw;
            // To animate caustics we need to apply _Time for it to increase UV each time
            uv += _Speed1 * _Time.y;
            // RGB split of resampled pixel (we need to move UV with s offset and resample)
            fixed s = _SplitRGB / 10;
            fixed r = tex2D(_CausticsTex, uv + fixed2(+s, +s)).r;
            fixed g = tex2D(_CausticsTex, uv + fixed2(+s, -s)).g;
            fixed b = tex2D(_CausticsTex, uv + fixed2(-s, -s)).b;
            fixed3 caustics1 = fixed3(r, g, b);
            // ------------ Second caustics sampling ----------------
            uv = uvTex * _Caustics_ST2.xy + _Caustics_ST2.zw;
            uv += _Speed2 * _Time.y;
            // RGB split of resampled pixel
            r = tex2D(_CausticsTex, uv + fixed2(+s, +s)).r;
            g = tex2D(_CausticsTex, uv + fixed2(+s, -s)).g;
            b = tex2D(_CausticsTex, uv + fixed2(-s, -s)).b;
            fixed3 caustics2 = fixed3(r, g, b);
            // Blending the two patterns using the min operator
            return min(caustics1, caustics2) * _Intensity;
        }

        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            float2 uv = float2(IN.uv_MainTex.x, IN.uv_MainTex.y/1.5);
            // Sample Main texture and multiply it with Color
            fixed4 c = tex2D (_MainTex, uv) * _Color;
            o.Albedo = c.rgb;
            // If fragment Y position is not above _MaxHeight (water) apply caustics
            if (IN.worldPos.y < _MaxHeight)
                // Caustics will end on clear line at _MaxHeight which we dont want
                // So we add second multiplicator to fade caustics as it is closer to _MaxHeight
                o.Albedo.rgb += caustics(IN.uv_MainTex) * abs(min(1, ((_MaxHeight - IN.worldPos.y) / _MaxHeight))) * 2;

            o.Metallic = _Metallic;
            o.Smoothness = _Glossiness;
            o.Alpha = c.a;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
