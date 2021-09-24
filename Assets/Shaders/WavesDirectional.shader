Shader "Custom/WavesDirectional"
{
    Properties
    {
        [Header(Main)]
        _Color("Color", Color) = (1,1,1,1)
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

        [Header(Direction)]
        [NoScaleOffset] _MainTex("AG Derivatives, B Height", 2D) = "black" {}
        [NoScaleOffset] _FlowMap("RG Flow, B speed, A noise", 2D) = "black" {}
        _Tiling("Tiling", Float) = 1
        _TilingModulated("Tiling, Modulated", Float) = 1
        _Speed("Speed", Float) = 1
        _FlowStrength("Flow Strength", Float) = 1
        _HeightScale("Constant Height Scale", Float) = 0.25
        _HeightScaleModulated("Modulated Height Scale", Float) = 0.75
        _GridResolution("Grid Resolution", Float) = 10

    }
        SubShader 
        {
            Tags { "RenderType" = "Transparent" "Queue" = "Transparent"}
            LOD 200
            CULL OFF
            // To adjust the color of the background (refraction and fog), we have to retrieve it with GrabPass
            // Just before the water gets drawn, what's rendered up to this points gets copied to a grab-pass texture (_WaterBackground).
            // It is then sent _WaterBackground to LookingThroughWater.cginc
            GrabPass{"_WaterBackground"}
            CGPROGRAM
            // Physically based Standard lighting model, and enable shadows on all light types
            #pragma surface surf Standard  alpha finalcolor:ResetAlphaAtEnd vertex:vert addshadow

            // Use shader model 3.0 target, to get nicer looking lighting
            #pragma target 3.0
            // Flow.cginc has functions which will take UV and flow parameters and returns the new flowed UV coordinates for distortional or directional flow.
            #include "Flow.cginc"
            // LookingThroughWater.cginc will return color of the fragment behind water. We provide:
            // 1. fragments screen position for function to be able to get depth texture
            // 2. tangent-space normal vector (XY coordinates) for the UV offset to wiggle and creates fake refraction
            // At output we receive RGB which we will apply to Emission
            #include "LookingThroughWater.cginc"

            // Skybox cubemap to calculate reflections
            samplerCUBE _CubeMap;
            // _MainTex is noise texure, _FlowMap is texture that contains 2D flow vectors with noise in A channel and speed in B channel
            sampler2D _MainTex, _FlowMap;
            // Directional flow parameters
            float _Tiling, _Speed, _FlowStrength, _HeightScale, _TilingModulated, _HeightScaleModulated, _GridResolution;
            // Reflection strength
            float _ReflectionStrength;
            // Since single wave isnt realistic, there are total of 4 different waves
            float4 _WaveA, _WaveB, _WaveC, _WaveD;

            struct Input
            {
                // UV coords, screen position for Refraction and Fog
                float2 uv_MainTex;
                float4 screenPos;
                // View direction and world reflection vector (world space direction of a mirror reflection using the vertex interpolated surface normal) for reflection
                float3 viewDir;
                float3 worldRefl;
                // INTERNAL_DATA is defined by the surface shader translator and it contains WorldReflectionVector
                INTERNAL_DATA
            };

            half _Glossiness;
            half _Metallic;
            fixed4 _Color;

            float3 GerstnerWave(float4 wave, float3 p, inout float3 tangent, inout float3 binormal) {
                float wavelength = wave.w;
                // Create the wave number (k) for easier calculations (2*PI/lambda)
                float k = 2 * UNITY_PI / wavelength;
                // Amplitude is equal to steepness (from 0 to 1) divided by the wave number (k)
                float steepness = wave.z;
                float amplitude = steepness / k;
                // In real life, speed of waves is determined by gravity and the wave number. This is case for deep water
                // while speed of shallow water is also affected by depth
                float c = sqrt(9.8 / k);

                // We need wave direction to be purely an indication of direction (unit lenght) so we need to normalize it
                float2 dir = normalize(wave.xy);
                // Wave function. We will take sin and cos as well as derivative of this function to 
                // calculate tangent, binormal and vertex position 
                // Since wave will move in X and Z direction, vertex position is modulated by variable dir (direction)
                // dir.xy represents direction of vertex X & Z components
                float function = k * (dot(dir, p.xz) - c * _Time.y);

                // Final vertex position calculation P = [p.x + dir.x * amp * cos(function), amp * sin(function), p.z + dir.z * amp * cos(function)]

                // We calculate partial derivative of function for x and z component for tangent and binormal, respectively
                // f'x = k * dir.x, f'z = k * dir.z
                // Then we do partial derivative of P (of X component for tangent and Z component for binormal)
                tangent += float3(
                    -dir.x * dir.x * (steepness * sin(function)),
                    dir.x * (steepness * cos(function)),
                    -dir.x * dir.y * (steepness * sin(function)));
                binormal += float3(
                    -dir.x * dir.y * (steepness * sin(function)),
                    dir.y * (steepness * cos(function)),
                    -dir.y * dir.y * (steepness * sin(function)));
                // Vertex position which we will add to initial vertex position (dir.y = dir.z from previous calculations)
                // Since we want multiple waves, it is simply a matter of adding all their offsets (we dont need x + and z + for X and Z component)
                return float3(
                    dir.x * (amplitude * cos(function)),
                    amplitude * sin(function),
                    dir.y * (amplitude * cos(function)));
            }

            float3 ScaleAndUnpackDerivative(float4 textureData) {
                // Unpack derivatives from channels A & G, and height from channel B
                float3 dh = textureData.agb;
                // Scale derivatives from 0 to 1 -> -1 to 1. Height isnt scaled because it does not have direction 
                dh.xy = dh.xy * 2 - 1;
                return dh;
            }

            float3 FlowCell(float2 uv, float2 offset, float time, bool gridB) {
                // Instead of sampling at the bottom left corner of each tile, we want to sample from center of each tile.
                // To do that we need to take 1 minus the unscaled offset and divide by 2
                float2 shift = (1 - offset) * 0.5;
                // Offset needs to be halved because we used whole numbers as offset arguments
                offset /= 2;
                // In case of second grid we need to move shift and offset a little bit
                if (gridB) {
                    shift -= 0.25;
                    offset += 0.25;
                }
                // We want to find compromise between the perfect result of a uniform flow and the desired result of using a different flow direction per fragment.
                // Solution is to split surface into tiles and then blend them between each other.
                // floor(uv * _GridResolution)/_GridResolution creates Staircase pattern with _GridResolution stairs.
                float2 uv_t = (floor(uv * _GridResolution + offset) + shift) / _GridResolution;

                // Sample flow vector (RG) and speed (B) from Flow texture 
                float3 flow = tex2D(_FlowMap, uv_t).rgb;
                // Scale flow vector (from 0 to 1) to -1 to 1.
                flow.xy = flow.xy * 2 - 1;
                // Speed doesnt have direction so it does not need scale but we multiply it with _FlowStrength multiplier to control speed.
                flow.z *= _FlowStrength;

                // Flow speed multiplied with the modulated tiling, plus the original constant tiling.
                float tiling = flow.z * _TilingModulated + _Tiling;

                // Lighting is affected by changes in position, but not rotation, which causes normals to be wrong when we rotate pattern.
                // Solution is to rotate derivates (its same as rotating normal vector) and rotation will be stored in derivRotation by DirectionalFlowUV.
                float2x2 derivRotation;
                float2 uv_f = DirectionalFlowUV(uv + offset, flow, tiling, time, derivRotation);

                // From RGBA color from texture MainTex to scaled derivatives (RG) and heigth of waves (B)
                float3 dh = ScaleAndUnpackDerivative(tex2D(_MainTex, uv_f));
                // Rotate the derivatives with rotation matrix we created in DirectionalFlowUV so we get correct normal vector
                dh.xy = mul(derivRotation, dh.xy);
                // Scale the strength of the derivative and height data, both using a constant factor and modulated by the flow strength.
                dh *= flow.z * _HeightScaleModulated + _HeightScale;
                return dh;
            }

            float3 FlowGrid(float2 uv, float time, bool gridB) {
                // We need to blend each tile in horizontal and vertical direction.
                // Solution is to sample cell to the left, right and up, down.
                float3 dhA = FlowCell(uv, float2(0, 0), time, gridB);
                float3 dhB = FlowCell(uv, float2(1, 0), time, gridB);
                float3 dhC = FlowCell(uv, float2(0, 1), time, gridB);
                float3 dhD = FlowCell(uv, float2(1, 1), time, gridB);

                // After sampling nearby cells, we need to average them out. This is done by linear interpolation of weights by coef.
                float2 coef = uv * _GridResolution;
                // If its second grid, add offset to t
                if (gridB) {
                    coef += 0.25;
                }
                // frac(t) will be in range(0,1), t will be in range(-1,1)
                coef = abs(2 * frac(coef) - 1);
                // Calculating weights for each cell
                float wA = (1 - coef.x) * (1 - coef.y);
                float wB = coef.x * (1 - coef.y);
                float wC = (1 - coef.x) * coef.y;
                float wD = coef.x * coef.y;
                // Applying weights to each cell derivative
                return dhA * wA + dhB * wB + dhC * wC + dhD * wD;
            }

            void ResetAlphaAtEnd(Input IN, SurfaceOutputStandard o, inout fixed4 color) {
                // Since we already calculated how much is the background visible, we dont need to do it twice
                // Only thing we need to do is to reset alpha to 1
                color.a = 1;
            }

            void vert(inout appdata_full vertexData) {
                // Store vertex position in variable p
                float3 p = vertexData.vertex.xyz;
                float3 tangent = float3(1, 0, 0);
                float3 binormal = float3(0, 0, 1);
                // Gerstner waves are also known as trochoidal waves, named after their shape,
                // or periodic surface gravity waves, which describes their physical nature.
                // Each surface points moves in a circle, orbiting a fixed anchor point. As the crest of a wave approaches, 
                // the point moves toward it. After the crest passes, it slides back, and then the next crest comes along. 
                // The result is that water bunches up in crests and spreads out in troughs, and the same will happen to our vertices.
                p += GerstnerWave(_WaveA, vertexData.vertex.xyz, tangent, binormal);
                p += GerstnerWave(_WaveB, vertexData.vertex.xyz, tangent, binormal);
                p += GerstnerWave(_WaveC, vertexData.vertex.xyz, tangent, binormal);
                p += GerstnerWave(_WaveD, vertexData.vertex.xyz, tangent, binormal);

                // The normal vector is the cross product of both tangent vectors.
                float3 normal = normalize(cross(binormal, tangent));

                // Apply calculations we have done on variable p to vertex position
                vertexData.vertex.xyz = p;
                // Change normals to fit waves we created
                vertexData.normal = normal;
            }

            void surf(Input IN, inout SurfaceOutputStandard o)
            {
                // Get tex coordinates and scaled to _Tiling - bigger the _Tiling, bigger the uv, more details 
                float2 uv = IN.uv_MainTex;
                float time = _Time.y * _Speed;
                // We need to sample from two grids (A & B)
                float3 dh = FlowGrid(uv, time, false);
                // and average them out
                dh = (dh + FlowGrid(uv, time, true)) * 0.5;

                // Normals are normalized derivatives we calculated in FlowGrid function
                // With normal vector texture we would use built in UnpackNormal function and even though result is almost identical our normals are cheaper to compute.
                o.Normal = normalize(float3(-dh.xy, 1));

                // Output color is height of waves multiplied by Color from inspector
                fixed4 color = dh.z * 1.5 *_Color;
                color.a = _Color.a;
                o.Albedo = color.rgb;

                o.Metallic = _Metallic;
                o.Smoothness = _Glossiness;
                o.Alpha = color.a;

                // Since the albedo is affected by lighting, we must add the underwater color and reflection to the surface lighting, 
                // which we can do by using it as the emissive color. We must modulate underwater fog by the water's alpha.
                o.Emission = ColorBelowWater(IN.screenPos, o.Normal * 20) * (1 - color.a)
                    // We cant use worldRefl declared in Input because it uses per vertex normal calculations and surf function uses per pixel calculations
                    // We need to use WorldReflectionVector function which returns reflection vector based on per-pixel normal map
                    // Then we sample CubeMap with that vector and get color which will fade as angle between IN.viewDir and o.Normal becomes smaller (camera above surface -> reflection = 0).
                    // _ReflectionStrength is used to control reflection strength
                    + texCUBE(_CubeMap, WorldReflectionVector(IN, o.Normal)).rgb * (1 - dot(IN.viewDir, o.Normal)) * (1 - _ReflectionStrength);
            }
            ENDCG
        }
            FallBack "Diffuse"
}
