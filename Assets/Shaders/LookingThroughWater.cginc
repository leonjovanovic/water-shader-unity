#if !defined(LOOKING_THROUGH_WATER_INCLUDED)
#define LOOKING_THROUGH_WATER_INCLUDED

// Unity makes the depth buffer globally available via the _CameraDepthTexture variable
// GrabPass will retreive texture that was rendered before water
sampler2D _CameraDepthTexture, _WaterBackground;
float4 _CameraDepthTexture_TexelSize;

float3 _WaterFogColor;
float _WaterFogDensity, _RefractionStrength, _RefractionStrength2;

// Fix blending when sampling the grabbed texture
// (to remove thin line of artifacts around the edge of the refraction)
float2 FixBlending(float2 uv) {
	#if UNITY_UV_STARTS_AT_TOP
	if (_CameraDepthTexture_TexelSize.y < 0) {
		uv.y = 1 - uv.y;
	}
	#endif
	return	(floor(uv * _CameraDepthTexture_TexelSize.zw) + 0.5) * abs(_CameraDepthTexture_TexelSize.xy);
}


// Returns rgb of fragments under the water on which refraction and underwater fog has been applied to.
float3 ColorBelowWater(float4 screenPos, float3 tangentSpaceNormal) {
	// To make the offset wiggle, we'll use the XY coordinates of the tangent-space normal vector as the offset
	// It will be synced with the apparent motion of surface
	float2 offset = tangentSpaceNormal.xy * _RefractionStrength;
	// If water is still, we need to move background a bit to simulate refraction
	if (offset.x == 0 && offset.y == 0) {
		offset = _RefractionStrength2;
	}
	// Diagonal offset is not symmetrical. The vertical offset is less than the horizontal.
	// To equalize the offsets, we have to multiply the V offset by the image width divided by its height
	// Z & W component of _CameraDepthTexture_TexelSize contain width & height in pixels
	// Y is reciprocal of the height so we can multiply with Y instead of dividing with W (Y can be negative hence abs)
	offset.y *= _CameraDepthTexture_TexelSize.z * abs(_CameraDepthTexture_TexelSize.y);
	float2 uv;
	// We have to convert to screen-space coordinates, by dividing X and Y by W.
	if(screenPos.w != 0)
		uv = FixBlending((screenPos.xy + offset) / screenPos.w);

	// Sample the background depth (behind water relative to the screen) via the SAMPLE_DEPTH_TEXTURE macro,
	// and then convert the raw value to the linear depth via the LinearEyeDepth function.
	float bgDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
	// We need to know the distance between the water and the screen
	// Solution is to take screenPos.z, which is interpolated clip space depth and converting it to linear depth
	float surfDepth = UNITY_Z_0_FAR_FROM_CLIPSPACE(screenPos.z);
	// The underwater depth is found by subtracting the surface depth from the background depth.
	float depthDelta = bgDepth - surfDepth;

	// Scale offset with depth difference. Depth is saturated (<0 = 0, >1 = 1) to range between 0 and 1.
	// We do this to eliminate possible incorrect refractions near surface. With saturation and scaling,
	// we eliminate near surface refractionsa
	offset *= saturate(depthDelta);
	// Recalculate UV with new offset
	if (screenPos.w != 0)
		uv = FixBlending((screenPos.xy + offset) / screenPos.w);
	// Recalculate depth difference with correct UV
	bgDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
	depthDelta = bgDepth - surfDepth;

	// Sample color from _WaterBackground which represents color of fragment behind water
	float3 bgColor = tex2D(_WaterBackground, uv).rgb;
	// Calculate how much we want to apply fog based on _WaterFogDensity and how much away is the fragment from water
	float fogCoef = exp2(-_WaterFogDensity/10 * depthDelta);
	// Linear interpolation of fog color and background color based on fogFactor as weight
	return lerp(_WaterFogColor, bgColor, fogCoef);
}

#endif