#if !defined(FLOW_INCLUDED)
#define FLOW_INCLUDED

// Distortional water. Take UV and flow parameters and returns the new flowed UV coordinates for distortional flow.
float3 FlowUVW(float2 uv, float2 flowVector, float2 jump, float flowOffset, float tiling, float time, bool flowB) {
	// FlowA needs to be 0 when FlowB is 1 and vice versa for transition to disappear. That is achieved with 0.5 offset for second flow
	float offset;
	if (flowB)
		offset = 0.5;
	else
		offset = 0;
	// Frac takes only decimal part of number to get 0-1 pattern (0 to 1 , then resets to 0)
	float progress0to1 = frac(time + offset);
	float3 uvw;
	// Subtract flow multiplied by progress0to1 from UV. We subtract so the flow goes in the direction of the vector
	// FlowOffset is variable that will control where the animation starts (default at 0)
	uvw.xy = uv - flowVector * (progress0to1 + flowOffset);
	// We need separate tiling property because we dont want to affect flowing. Thats why we cant use tiling and offset
	// of the surface shader and thats why we need to apply it after adding flow and before adding offset.
	// Adding phase offset for flowB
	// Apply UV jump for longer single lopp. We need to multiply it with integer portion of the time.
	uvw.xy = uvw.xy * tiling + offset + (time - progress0to1) * jump;
	// Calculate weight which will make each flow fade based on their position. We will use Seesaw pattern,
	// where weight is minimum (0) in 0, 1, 2 ... and maximum (1) in 1/2, 3/2, ... (∧∧∧)
	// When we overlap two distortion where one has offset of 0.5 (XXXXXX) and we fade flows as it comes 
	// near minimum, we get smooth transitions between animations
	uvw.z = 1 - abs(1 - 2 * progress0to1);
	return uvw;
}

// Directional water. Take UV and flow parameters and returns the new flowed UV coordinates for directional flow.
float2 DirectionalFlowUV(float2 uv, float3 flowVectorAndSpeed, float tiling, float time, out float2x2 rotationMatrix) {
	// Flow map doesn't contain vectors of unit length, we have to normalize them first.
	float2 direction = normalize(flowVectorAndSpeed.xy);
	// Calculate rotation by creating Rotation matrix where sinA = direction.x and cosA = direction.y
	rotationMatrix = float2x2(direction.y, -direction.x, direction.x, direction.y);
	// Rotate UV with rotation matrix
	uv = mul(rotationMatrix, uv);
	// Since UV are normalized we need to apply speed that we stored in _FlowMap B channel
	uv.y -= time * flowVectorAndSpeed.z;
	// Apply tiling
	return uv * tiling;
}
#endif