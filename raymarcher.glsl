precision mediump float;

uniform vec2 u_resolution;
uniform vec2 u_mouse;
uniform float u_time;
uniform vec3 u_camera;

#define FAR 30. //max distance
#define NEAR 0.2 //min distance
#define EPS 0.0001 //epsilon
#define MAX_STEPS 96
uniform vec3 SKY_COLOR;// = vec3(0.0863, 0.0863, 0.0863);
uniform vec3 cube_color_1, cube_color_2;
uniform vec3 LIGHT_COLOR;
uniform float MAX_REFLECTIONS;
uniform float CUTOUT_RADIUS;
// uniform int FOG_COLOR
#define FOG_COLOR SKY_COLOR
uniform float FOG_DENSITY;
#define FOG_SAMPLES 20.
#define FOG_SAMPLE_DIST .1
#define FOG_WEIGHT 1./20.

mat3 rotationY( in float angle ) {
	return mat3(	cos(angle),		0,		sin(angle),
			 				0,		1.0,			 0,
					-sin(angle),	0,		cos(angle));
}

vec3 pMod3(inout vec3 p, vec3 size) {
	vec3 c = floor((p + size*0.5)/size);
	p = mod(p + size*0.5, size) - size*0.5;
	return c;
}

float sphere(vec3 point, float radius){
    return length(point)-radius;
}

float roundBox( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float boolXor(float a, float b){
    return (a-b)*(a-b);
}

// Returns albedo of surface
vec3 getColor(vec3 point, out vec3 emission){
    
    vec3 lightP = floor(mod(point-.5, 4.)*.5);
    // 1 corner of each 2x2 grid glows
    emission = 3.*lightP.x*lightP.y*lightP.z * LIGHT_COLOR;
    
    point = floor(mod(point-.5, 4.)*.5);

    // Alternate between primary and secondary colors
    float mask = boolXor(point.x, boolXor(point.y, point.z));
    return mix(
        cube_color_1,
        cube_color_2,
        mask
    );
}

// SDF of world; generates tiled cubes with sphere cut out of them
float world(vec3 point){
    vec3 p = point;
    pMod3(p, vec3(2.));
    float dist = FAR;
    
    dist = min(
        sphere(point, .25), 
        max(
            max(
                -sphere(p, 0.33),
                roundBox(p, vec3(.3), 0.)
            ),
            -sphere(abs(p)-vec3(.25), CUTOUT_RADIUS)
        )
    );
    
    return dist;
}

vec3 getNormal(vec3 point){
    //Gradient method of determining normal
    float dist = world(point);
    vec3 d = vec3(EPS, 0., 0.);
    return -normalize(vec3(
        dist - world(point+d.xyz),
        dist - world(point+d.yxz),
        dist - world(point+d.yzx)
    ));
}

// Intersects a ray with the world
float trace(vec3 rayDir, vec3 rayOrigin, float far){
    float t = NEAR, d;
    for (int i = 0; i < MAX_STEPS; i++){
        d = world(rayDir*t + rayOrigin);
        t += d;
        if(abs(d) < EPS || t > far) return t;
    }
    return far;
}

float trace(vec3 rayDir, vec3 rayOrigin){
    return trace(rayDir, rayOrigin, FAR);
}

// Gets surface information (albedo, normal, etc) by intersecting a ray with the world
vec3 render(vec3 rayDir, vec3 rayOrigin, out vec3 hitPoint, out vec3 hitNormal, out vec3 baseColor, out float depth){
    depth = trace(rayDir, rayOrigin);

    hitPoint = rayOrigin+rayDir*depth;

    vec3 color;
    if(depth < FAR){
        hitNormal = getNormal(hitPoint);
        vec3 emission;
        baseColor = getColor(hitPoint, emission);
        color += emission;
    }
    else{
        color = SKY_COLOR;//skyColor(rayDir);
    }
    return color;
}

void main() {
    float u_time = -u_time;

    float focalLength = 1.;
    vec3 rayDir;
    vec3 rayOrigin;

    rayOrigin.xz = vec2(-sin(u_time*.3), cos(-u_time*.3));

    vec3 totalColor;
    
    // Generate rays from screen coordinates
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    uv = uv*2.-1.;
    uv.x *= u_resolution.x / u_resolution.y;
    rayDir = rotationY(u_time*.3)*normalize(vec3(uv, focalLength));
    
    vec3 color;
    vec3 n, r = rayDir, p, c;
    float d;

    // Initial color
    color = render(rayDir, rayOrigin, p, n, c, d);
    // Volumetric fog light samples
    float d0 = d;
    float foglight, fogStrength;
    float sampleWeight = FOG_WEIGHT;
    for(float j = 1.; j < FOG_SAMPLES+1.; j++){
        float currentD = j*FOG_SAMPLE_DIST;
        vec3 p = rayOrigin + r*currentD;
        //FAKE LIGHT SAMPLING; only works for 
        pMod3(p, vec3(2.));
        p = abs(p);
        foglight += step(0.3, min(p.x, p.z));
        
        if(currentD > d){
            sampleWeight = 1./j;
            break;
        }
    }
    foglight *= sampleWeight;

    // Reflections
    for(float i = 1.; i < 5.; i++){
        if (i > MAX_REFLECTIONS) break;

        r = reflect(r, n);
        vec3 baseColor;
        vec3 hitColor = render(r, p, p, n, baseColor, d);
        
        float fogStrength = exp(-FOG_DENSITY*d);
        color += c*mix(FOG_COLOR, hitColor, fogStrength);
        // Attenuate future reflections by total albedo
        c *= baseColor*fogStrength*FOG_COLOR;
        if(max(c.x, max(c.y, c.z)) < EPS){
            break;
        }
    }
    
    // Apply fog
    totalColor += mix(foglight*FOG_COLOR, color, exp(-FOG_DENSITY*d0));
    gl_FragColor = vec4(totalColor, 1.0);
}