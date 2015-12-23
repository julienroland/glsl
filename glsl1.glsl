////////////////////////////////////////////////////////////////
//
//                           HG_SDF
//
//     GLSL LIBRARY FOR BUILDING SIGNED DISTANCE BOUNDS
//
//     version 2015-12-15 (initial release)
//
//     Check http://mercury.sexy/hg_sdf for updates
//     and usage examples. Send feedback to spheretracing@mercury.sexy.
//
//     Brought to you by MERCURY http://mercury.sexy
//
//
//
// Released as Creative Commons Attribution-NonCommercial (CC BY-NC)
//
////////////////////////////////////////////////////////////////
//
// How to use this:
//
// 1. Build some system to #include glsl files in each other.
//   Include this one at the very start. Or just paste everywhere.
// 2. Build a sphere tracer. See those papers:
//   * "Sphere Tracing" http://graphics.cs.illinois.edu/sites/default/files/zeno.pdf
//   * "Enhanced Sphere Tracing" http://lgdv.cs.fau.de/get/2234
//   The Raymnarching Toolbox Thread on pouet can be helpful as well
//   http://www.pouet.net/topic.php?which=7931&page=1
//   and contains links to many more resources.
// 3. Use the tools in this library to build your distance bound f().
// 4. ???
// 5. Win a compo.
//
// (6. Buy us a beer or a good vodka or something, if you like.)
//
////////////////////////////////////////////////////////////////
//
// Table of Contents:
//
// * Helper functions and macros
// * Collection of some primitive objects
// * Domain Manipulation operators
// * Object combination operators
//
////////////////////////////////////////////////////////////////
//
// Why use this?
//
// The point of this lib is that everything is structured according
// to patterns that we ended up using when building geometry.
// It makes it more easy to write code that is reusable and that somebody
// else can actually understand. Especially code on Shadertoy (which seems
// to be what everybody else is looking at for "inspiration") tends to be
// really ugly. So we were forced to do something about the situation and
// release this lib ;)
//
// Everything in here can probably be done in some better way.
// Please experiment. We'd love some feedback, especially if you
// use it in a scene production.
//
// The main patterns for building geometry this way are:
// * Stay Lipschitz continuous. That means: don't have any distance
//   gradient larger than 1. Try to be as close to 1 as possible -
//   Distances are euclidean distances, don't fudge around.
//   Underestimating distances will happen. That's why calling
//   it a "distance bound" is more correct. Don't ever multiply
//   distances by some value to "fix" a Lipschitz continuity
//   violation. The invariant is: each fSomething() function returns
//   a correct distance bound.
// * Use very few primitives and combine them as building blocks
//   using combine opertors that preserve the invariant.
// * Multiply objects by repeating the domain (space).
//   If you are using a loop inside your distance function, you are
//   probably doing it wrong (or you are building boring fractals).
// * At right-angle intersections between objects, build a new local
//   coordinate system from the two distances to combine them in
//   interesting ways.
// * As usual, there are always times when it is best to not follow
//   specific patterns.
//
////////////////////////////////////////////////////////////////
//
// FAQ
//
// Q: Why is there no sphere tracing code in this lib?
// A: Because our system is way too complex and always changing.
//    This is the constant part. Also we'd like everyone to
//    explore for themselves.
//
// Q: This does not work when I paste it into Shadertoy!!!!
// A: Yes. It is GLSL, not GLSL ES. We like real OpenGL
//    because it has way more features and is more likely
//    to work compared to browser-based WebGL. We recommend
//    you consider using OpenGL for your productions. Most
//    of this can be ported easily though.
//
// Q: How do I material?
// A: We recommend something like this:
//    Write a material ID, the distance and the local coordinate
//    p into some global variables whenever an object's distance is
//    smaller than the stored distance. Then, at the end, evaluate
//    the material to get color, roughness, etc., and do the shading.
//
// Q: I found an error. Or I made some function that would fit in
//    in this lib. Or I have some suggestion.
// A: Awesome! Drop us a mail at spheretracing@mercury.sexy.
//
// Q: Why is this not on github?
// A: Because we were too lazy. If we get bugged about it enough,
//    we'll do it.
//
// Q: Your license sucks for me.
// A: Oh. What should we change it to?
//
// Q: I have trouble understanding what is going on with my distances.
// A: Some visualization of the distance field helps. Try drawing a
//    plane that you can sweep through your scene with some color
//    representation of the distance field at each point and/or iso
//    lines at regular intervals. Visualizing the length of the
//    gradient (or better: how much it deviates from being equal to 1)
//    is immensely helpful for understanding which parts of the
//    distance field are broken.
//
////////////////////////////////////////////////////////////////






////////////////////////////////////////////////////////////////
//
//             HELPER FUNCTIONS/MACROS
//
////////////////////////////////////////////////////////////////

#define PI (3.14159265)
#define TAU (2.*PI)
#define PHI (sqrt(5.)*0.5 + 0.5)

// Clamp to [0,1] - this operation is free under certain circumstances.
// For further information see
// http://www.humus.name/Articles/Persson_LowLevelThinking.pdf and
// http://www.humus.name/Articles/Persson_LowlevelShaderOptimization.pdf
#define saturate(x) clamp(x, 0., 1.)

// Sign function that doesn't return 0
float sgn(float x) {
	return (x<0.)?-1.:1.;
}

float square (float x) {
	return x*x;
}

vec2 square (vec2 x) {
	return x*x;
}

vec3 square (vec3 x) {
	return x*x;
}

float lengthSqr(vec3 x) {
	return dot(x, x);
}


// Maximum/minumum elements of a vector
float vmax(vec2 v) {
	return max(v.x, v.y);
}

float vmax(vec3 v) {
	return max(max(v.x, v.y), v.z);
}

float vmax(vec4 v) {
	return max(max(v.x, v.y), max(v.z, v.w));
}

float vmin(vec2 v) {
	return min(v.x, v.y);
}

float vmin(vec3 v) {
	return min(min(v.x, v.y), v.z);
}

float vmin(vec4 v) {
	return min(min(v.x, v.y), min(v.z, v.w));
}




////////////////////////////////////////////////////////////////
//
//             PRIMITIVE DISTANCE FUNCTIONS
//
////////////////////////////////////////////////////////////////
//
// Conventions:
//
// Everything that is a distance function is called fSomething.
// The first argument is always a point in 2 or 3-space called <p>.
// Unless otherwise noted, (if the object has an intrinsic "up"
// side or direction) the y axis is "up" and the object is
// centered at the origin.
//
////////////////////////////////////////////////////////////////

float fSphere(vec3 p, float r) {
	return length(p) - r;
}

// Plane with normal n (n is normalized) at some distance from the origin
float fPlane(vec3 p, vec3 n, float distanceFromOrigin) {
	return dot(p, n) + distanceFromOrigin;
}

// Cheap Box: distance to corners is overestimated
float fBoxCheap(vec3 p, vec3 b) { //cheap box
	return vmax(abs(p) - b);
}

// Box: correct distance to corners
float fBox(vec3 p, vec3 b) {
	vec3 d = abs(p) - b;
	return length(max(d, vec3(0))) + vmax(min(d, vec3(0)));
}

// Same as above, but in two dimensions (an endless box)
float fBox2Cheap(vec2 p, vec2 b) {
	return vmax(abs(p)-b);
}

float fBox2(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0))) + vmax(min(d, vec2(0)));
}


// Endless "corner"
float fCorner (vec2 p) {
	return length(max(p, vec2(0))) + vmax(min(p, vec2(0)));
}

// Blobby ball object. You've probably seen it somewhere. This is not a correct distance bound, beware.
float fBlob(vec3 p) {
	p = abs(p);
	if (p.x < max(p.y, p.z)) p = p.yzx;
	if (p.x < max(p.y, p.z)) p = p.yzx;
	float b = max(max(max(
		dot(p, normalize(vec3(1, 1, 1))),
		dot(p.xz, normalize(vec2(PHI+1., 1.)))),
		dot(p.yx, normalize(vec2(1., PHI)))),
		dot(p.xz, normalize(vec2(1., PHI))));
	float l = length(p);
	return l - 1.5 - 0.2 * (1.5 / 2.)* cos(min(
        sqrt(1.01 - b / l)
        * PI / 0.25, PI
    ));
}

// Cylinder standing upright on the xz plane
float fCylinder(vec3 p, float r, float height) {
	float d = length(p.xz) - r;
	d = max(d, abs(p.y) - height);
	return d;
}

// Capsule: A Cylinder with round caps on both sides
float fCapsule(vec3 p, float r, float c) {
	return mix(length(p.xz) - r, length(vec3(p.x, abs(p.y) - c, p.z)) - r, step(c, abs(p.y)));
}

// Distance to line segment between <a> and <b>, used for fCapsule() version 2below
float fLineSegment(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float t = saturate(dot(p - a, ab) / dot(ab, ab));
	return length((ab*t + a) - p);
}

// Capsule version 2: between two end points <a> and <b> with radius r
float fCapsule(vec3 p, vec3 a, vec3 b, float r) {
	return fLineSegment(p, a, b) - r;
}

// Torus in the XZ-plane
float fTorus(vec3 p, float smallRadius, float largeRadius) {
	return length(vec2(length(p.xz) - largeRadius, p.y)) - smallRadius;
}

// A circle line. Can also be used to make a torus by subtracting the smaller radius of the torus.
float fCircle(vec3 p, float r) {
	float l = length(p.xz) - r;
	return length(vec2(p.y, l));
}

// A circular disc with no thickness (i.e. a cylinder with no height).
// Subtract some value to make a flat disc with rounded edge.
float fDisc(vec3 p, float r) {
	float l = length(p.xz) - r;
	return l < 0. ? abs(p.y) : length(vec2(p.y, l));
}

// Hexagonal prism, circumcircle variant
float fHexagonCircumcircle(vec3 p, vec2 h) {
	vec3 q = abs(p);
	return max(q.y - h.y, max(q.x*sqrt(3.)*0.5 + q.z*0.5, q.z) - h.x);
	//this is mathematically equivalent to this line, but less efficient:
	//return max(q.y - h.y, max(dot(vec2(cos(PI/3), sin(PI/3)), q.zx), q.z) - h.x);
}

// Hexagonal prism, incircle variant
float fHexagonIncircle(vec3 p, vec2 h) {
	return fHexagonCircumcircle(p, vec2(h.x*sqrt(3.)*0.5, h.y));
}

// Cone with correct distances to tip and base circle. Y is up, 0 is in the middle of the base.
float fCone(vec3 p, float radius, float height) {
	vec2 q = vec2(length(p.xz), p.y);
	vec2 tip = q - vec2(0, height);
	vec2 mantleDir = normalize(vec2(height, radius));
	float mantle = dot(tip, mantleDir);
	float d = max(mantle, -q.y);
	float projected = dot(tip, vec2(mantleDir.y, -mantleDir.x));

	// distance to tip
	if ((q.y > height) && (projected < 0.)) {
		d = max(d, length(tip));
	}

	// distance to base ring
	if ((q.x > radius) && (projected > length(vec2(height, radius)))) {
		d = max(d, length(q - vec2(radius, 0.)));
	}
	return d;
}

//
// "Generalized Distance Functions" by Akleman and Chen.
// see the Paper at https://www.viz.tamu.edu/faculty/ergun/research/implicitmodeling/papers/sm99.pdf
//
// This set of constants is used to construct a large variety of geometric primitives.
// Indices are shifted by 1 compared to the paper because we start counting at Zero.
// Some of those are slow whenever a driver decides to not unroll the loop,
// which seems to happen for fIcosahedron und fTruncatedIcosahedron on nvidia 350.12 at least.
// Specialized implementations can well be faster in all cases.
//


const vec3 GDFVectors0 = normalize(vec3(1, 0, 0));
const vec3 GDFVectors1 = normalize(vec3(0, 1, 0));
const vec3 GDFVectors2 = normalize(vec3(0, 0, 1));

const vec3 GDFVectors3 = normalize(vec3(1, 1, 1 ));
const vec3 GDFVectors4 = normalize(vec3(-1, 1, 1));
const vec3 GDFVectors5 = normalize(vec3(1, -1, 1));
const vec3 GDFVectors6 = normalize(vec3(1, 1, -1));

const vec3 GDFVectors7 = normalize(vec3(0, 1, PHI+1.));
const vec3 GDFVectors8 = normalize(vec3(0, -1, PHI+1.));
const vec3 GDFVectors9 = normalize(vec3(PHI+1., 0, 1.));
const vec3 GDFVectors10 = normalize(vec3(-PHI-1., 0, 1.));
const vec3 GDFVectors11 = normalize(vec3(1, PHI+1., 0.));
const vec3 GDFVectors12 = normalize(vec3(-1, PHI+1., 0.));

const vec3 GDFVectors13 = normalize(vec3(0, PHI, 1));
const vec3 GDFVectors14 = normalize(vec3(0, -PHI, 1));
const vec3 GDFVectors15 = normalize(vec3(1, 0, PHI));
const vec3 GDFVectors16 = normalize(vec3(-1, 0, PHI));
const vec3 GDFVectors17 = normalize(vec3(PHI, 1, 0));
const vec3 GDFVectors18 = normalize(vec3(-PHI, 1, 0));

vec3 fGDFVector(int i) {
    if (i == 0) {
        return GDFVectors0;
    } else if (i == 1) {
        return GDFVectors1;
    } else if (i == 2) {
        return GDFVectors2;
    } else if (i == 3) {
        return GDFVectors3;
    } else if (i == 4) {
        return GDFVectors4;
    } else if (i == 5) {
        return GDFVectors5;
    } else if (i == 6) {
        return GDFVectors6;
    } else if (i == 7) {
        return GDFVectors7;
    } else if (i == 8) {
        return GDFVectors8;
    } else if (i == 9) {
        return GDFVectors9;
    } else if (i == 10) {
        return GDFVectors10;
    } else if (i == 11) {
        return GDFVectors11;
    } else if (i == 12) {
        return GDFVectors12;
    } else if (i == 13) {
        return GDFVectors13;
    } else if (i == 14) {
        return GDFVectors14;
    } else if (i == 15) {
        return GDFVectors15;
    } else if (i == 16) {
        return GDFVectors16;
    } else if (i == 17) {
        return GDFVectors17;
    } else if (i == 18) {
        return GDFVectors18;
    }
}

// Primitives follow:

float fOctahedron(vec3 p, float r, float e) {
	float d = 0.;
	for (int i = 3; i <= 6; ++i)
		d += pow(abs(dot(p, fGDFVector(i))), e);
	return pow(d, 1./e) - r;
}

float fDodecahedron(vec3 p, float r, float e) {
	float d = 0.;
	for (int i = 13; i <= 18; ++i)
		d += pow(abs(dot(p, fGDFVector(i))), e);
	return pow(d, 1./e) - r;
}

float fIcosahedron(vec3 p, float r, float e) {
	float d = 0.;
	for (int i = 3; i <= 12; ++i)
		d += pow(abs(dot(p, fGDFVector(i))), e);
	return pow(d, 1./e) - r;
}

float fTruncatedOctahedron(vec3 p, float r, float e) {
	float d = 0.;
	for (int i = 0; i <= 6; ++i)
		d += pow(abs(dot(p, fGDFVector(i))), e);
	return pow(d, 1./e) - r;
}

float fTruncatedIcosahedron(vec3 p, float r, float e) {
	float d = 0.;
	for (int i = 3; i <= 18; ++i)
		d += pow(abs(dot(p, fGDFVector(i))), e);
	return pow(d, 1./e) - r;
}

float fOctahedron(vec3 p, float r) {
    float d = 0.;
	for (int i = 3; i <= 6; ++i)
		d = max(d, abs(dot(p, fGDFVector(i))));
	return d - r;
}

float fDodecahedron(vec3 p, float r) {
    float d = 0.;
	for (int i = 13; i <= 18; ++i)
		d = max(d, abs(dot(p, fGDFVector(i))));
	return d - r;
}

float fIcosahedron(vec3 p, float r) {
    float d = 0.;
	for (int i = 3; i <= 12; ++i)
		d = max(d, abs(dot(p, fGDFVector(i))));
	return d - r;
}

float fTruncatedOctahedron(vec3 p, float r) {
    float d = 0.;
	for (int i = 0; i <= 6; ++i)
		d = max(d, abs(dot(p, fGDFVector(i))));
	return d - r;
}

float fTruncatedIcosahedron(vec3 p, float r) {
    float d = 0.;
	for (int i = 3; i <= 18; ++i)
		d = max(d, abs(dot(p, fGDFVector(i))));
	return d - r;
}

////////////////////////////////////////////////////////////////
//
//                DOMAIN MANIPULATION OPERATORS
//
////////////////////////////////////////////////////////////////
//
// Conventions:
//
// Everything that modifies the domain is named pSomething.
//
// Many operate only on a subset of the three dimensions. For those,
// you must choose the dimensions that you want manipulated
// by supplying e.g. <p.x> or <p.zx>
//
// <inout p> is always the first argument and modified in place.
//
// Many of the operators partition space into cells. An identifier
// or cell index is returned, if possible. This return value is
// intended to be optionally used e.g. as a random seed to change
// parameters of the distance functions inside the cells.
//
// Unless stated otherwise, for cell index 0, <p> is unchanged and cells
// are centered on the origin so objects don't have to be moved to fit.
//
//
////////////////////////////////////////////////////////////////



// Rotate around a coordinate axis (i.e. in a plane perpendicular to that axis) by angle <a>.
// Read like this: R(p.xz, a) rotates "x towards z".
// This is fast if <a> is a compile-time constant and slower (but still practical) if not.
void pR(inout vec2 p, float a) {
	p = cos(a)*p + sin(a)*vec2(p.y, -p.x);
}

// Shortcut for 45-degrees rotation
void pR45(inout vec2 p) {
	p = (p + vec2(p.y, -p.x))*sqrt(0.5);
}

// Repeat space along one axis. Use like this to repeat along the x axis:
// <float cell = pMod1(p.x,5);> - using the return value is optional.
float pMod1(inout float p, float size) {
	float halfsize = size*0.5;
	float c = floor((p + halfsize)/size);
	p = mod(p + halfsize, size) - halfsize;
	return c;
}

// Same, but mirror every second cell so they match at the boundaries
float pModMirror1(inout float p, float size) {
	float halfsize = size*0.5;
	float c = floor((p + halfsize)/size);
	p = mod(p + halfsize,size) - halfsize;
	p *= mod(c, 2.0)*2. - 1.;
	return c;
}

// Repeat the domain only in positive direction. Everything in the negative half-space is unchanged.
float pModSingle1(inout float p, float size) {
	float halfsize = size*0.5;
	float c = floor((p + halfsize)/size);
	if (p >= 0.)
		p = mod(p + halfsize, size) - halfsize;
	return c;
}

// Repeat only a few times: from indices <start> to <stop> (similar to above, but more flexible)
float pModInterval1(inout float p, float size, float start, float stop) {
	float halfsize = size*0.5;
	float c = floor((p + halfsize)/size);
	p = mod(p+halfsize, size) - halfsize;
	if (c > stop) { //yes, this might not be the best thing numerically.
		p += size*(c - stop);
		c = stop;
	}
	if (c <start) {
		p += size*(c - start);
		c = start;
	}
	return c;
}


// Repeat around the origin by a fixed angle.
// For easier use, num of repetitions is use to specify the angle.
float pModPolar(inout vec2 p, float repetitions) {
	float angle = 2.*PI/repetitions;
	float a = atan(p.y, p.x) + angle/2.;
	float r = length(p);
	float c = floor(a/angle);
	a = mod(a,angle) - angle/2.;
	p = vec2(cos(a), sin(a))*r;
	// For an odd number of repetitions, fix cell index of the cell in -x direction
	// (cell index would be e.g. -5 and 5 in the two halves of the cell):
	if (abs(c) >= (repetitions/2.)) c = abs(c);
	return c;
}

// Repeat in two dimensions
vec2 pMod2(inout vec2 p, vec2 size) {
	vec2 c = floor((p + size*0.5)/size);
	p = mod(p + size*0.5,size) - size*0.5;
	return c;
}

// Same, but mirror every second cell so all boundaries match
vec2 pModMirror2(inout vec2 p, vec2 size) {
	vec2 halfsize = size*0.5;
	vec2 c = floor((p + halfsize)/size);
	p = mod(p + halfsize, size) - halfsize;
	p *= mod(c,vec2(2.))*2. - vec2(1.);
	return c;
}

// Same, but mirror every second cell at the diagonal as well
vec2 pModGrid2(inout vec2 p, vec2 size) {
	vec2 c = floor((p + size*0.5)/size);
	p = mod(p + size*0.5, size) - size*0.5;
	p *= mod(c,vec2(2))*2. - vec2(1);
	p -= size/2.;
	if (p.x > p.y) p.xy = p.yx;
	return floor(c/2.);
}

// Repeat in three dimensions
vec3 pMod3(inout vec3 p, vec3 size) {
	vec3 c = floor((p + size*0.5)/size);
	p = mod(p + size*0.5, size) - size*0.5;
	return c;
}

// Mirror at an axis-aligned plane which is at a specified distance <dist> from the origin.
float pMirror (inout float p, float dist) {
	float s = sign(p);
	p = abs(p)-dist;
	return s;
}

// Mirror in both dimensions and at the diagonal, yielding one eighth of the space.
// translate by dist before mirroring.
vec2 pMirrorOctant (inout vec2 p, vec2 dist) {
	vec2 s = sign(p);
	pMirror(p.x, dist.x);
	pMirror(p.y, dist.y);
	if (p.y > p.x)
		p.xy = p.yx;
	return s;
}

// Reflect space at a plane
float pReflect(inout vec3 p, vec3 planeNormal, float offset) {
	float t = dot(p, planeNormal)+offset;
	if (t < 0.) {
		p = p - (2.*t)*planeNormal;
	}
	return sign(t);
}


////////////////////////////////////////////////////////////////
//
//             OBJECT COMBINATION OPERATORS
//
////////////////////////////////////////////////////////////////
//
// We usually need the following boolean operators to combine two objects:
// Union: OR(a,b)
// Intersection: AND(a,b)
// Difference: AND(a,!b)
// (a and b being the distances to the objects).
//
// The trivial implementations are min(a,b) for union, max(a,b) for intersection
// and max(a,-b) for difference. To combine objects in more interesting ways to
// produce rounded edges, chamfers, stairs, etc. instead of plain sharp edges we
// can use combination operators. It is common to use some kind of "smooth minimum"
// instead of min(), but we don't like that because it does not preserve Lipschitz
// continuity in many cases.
//
// Naming convention: since they return a distance, they are called fOpSomething.
// The different flavours usually implement all the boolean operators above
// and are called fOpUnionRound, fOpIntersectionRound, etc.
//
// The basic idea: Assume the object surfaces intersect at a right angle. The two
// distances <a> and <b> constitute a new local two-dimensional coordinate system
// with the actual intersection as the origin. In this coordinate system, we can
// evaluate any 2D distance function we want in order to shape the edge.
//
// The operators below are just those that we found useful or interesting and should
// be seen as examples. There are infinitely more possible operators.
//
// They are designed to actually produce correct distances or distance bounds, unlike
// popular "smooth minimum" operators, on the condition that the gradients of the two
// SDFs are at right angles. When they are off by more than 30 degrees or so, the
// Lipschitz condition will no longer hold (i.e. you might get artifacts). The worst
// case is parallel surfaces that are close to each other.
//
// Most have a float argument <r> to specify the radius of the feature they represent.
// This should be much smaller than the object size.
//
// Some of them have checks like "if ((-a < r) && (-b < r))" that restrict
// their influence (and computation cost) to a certain area. You might
// want to lift that restriction or enforce it. We have left it as comments
// in some cases.
//
// usage example:
//
// float fTwoBoxes(vec3 p) {
//   float box0 = fBox(p, vec3(1));
//   float box1 = fBox(p-vec3(1), vec3(1));
//   return fOpUnionChamfer(box0, box1, 0.2);
// }
//
////////////////////////////////////////////////////////////////


// The "Chamfer" flavour makes a 45-degree chamfered edge (the diagonal of a square of size <r>):
float fOpUnionChamfer(float a, float b, float r) {
	float m = min(a, b);
	//if ((a < r) && (b < r)) {
		return min(m, (a - r + b)*sqrt(0.5));
	//} else {
		return m;
	//}
}

// Intersection has to deal with what is normally the inside of the resulting object
// when using union, which we normally don't care about too much. Thus, intersection
// implementations sometimes differ from union implementations.
float fOpIntersectionChamfer(float a, float b, float r) {
	float m = max(a, b);
	if (r <= 0.) return m;
	if (((-a < r) && (-b < r)) || (m < 0.)) {
		return max(m, (a + r + b)*sqrt(0.5));
	} else {
		return m;
	}
}

// Difference can be built from Intersection or Union:
float fOpDifferenceChamfer (float a, float b, float r) {
	return fOpIntersectionChamfer(a, -b, r);
}

// The "Round" variant uses a quarter-circle to join the two objects smoothly:
float fOpUnionRound(float a, float b, float r) {
	float m = min(a, b);
	if ((a < r) && (b < r) ) {
		return min(m, r - sqrt((r-a)*(r-a) + (r-b)*(r-b)));
	} else {
	 return m;
	}
}

float fOpIntersectionRound(float a, float b, float r) {
	float m = max(a, b);
	if ((-a < r) && (-b < r)) {
		return max(m, -(r - sqrt((r+a)*(r+a) + (r+b)*(r+b))));
	} else {
		return m;
	}
}

float fOpDifferenceRound (float a, float b, float r) {
	return fOpIntersectionRound(a, -b, r);
}


// The "Columns" flavour makes n-1 circular columns at a 45 degree angle:
float fOpUnionColumns(float a, float b, float r, float n) {
	if ((a < r) && (b < r)) {
		vec2 p = vec2(a, b);
		float columnradius = r*sqrt(2.)/((n-1.)*2.+sqrt(2.));
		pR45(p);
		p.x -= sqrt(2.)/2.*r;
		p.x += columnradius*sqrt(2.);
		if (mod(n,2.) == 1.) {
			p.y += columnradius;
		}
		// At this point, we have turned 45 degrees and moved at a point on the
		// diagonal that we want to place the columns on.
		// Now, repeat the domain along this direction and place a circle.
		pMod1(p.y, columnradius*2.);
		float result = length(p) - columnradius;
		result = min(result, p.x);
		result = min(result, a);
		return min(result, b);
	} else {
		return min(a, b);
	}
}

float fOpDifferenceColumns(float a, float b, float r, float n) {
	a = -a;
	float m = min(a, b);
	//avoid the expensive computation where not needed (produces discontinuity though)
	if ((a < r) && (b < r)) {
		vec2 p = vec2(a, b);
		float columnradius = r*sqrt(2.)/n/2.0;
		columnradius = r*sqrt(2.)/((n-1.)*2.+sqrt(2.));

		pR45(p);
		p.y += columnradius;
		p.x -= sqrt(2.)/2.*r;
		p.x += -columnradius*sqrt(2.)/2.;

		if (mod(n,2.) == 1.) {
			p.y += columnradius;
		}
		pMod1(p.y,columnradius*2.);

		float result = -length(p) + columnradius;
		result = max(result, p.x);
		result = min(result, a);
		return -min(result, b);
	} else {
		return -m;
	}
}

float fOpIntersectionColumns(float a, float b, float r, float n) {
	return fOpDifferenceColumns(a,-b,r, n);
}

// The "Stairs" flavour produces n-1 steps of a staircase:
float fOpUnionStairs(float a, float b, float r, float n) {
	float d = min(a, b);
	vec2 p = vec2(a, b);
	pR45(p);
	p = p.yx - vec2((r-r/n)*0.5*sqrt(2.));
	p.x += 0.5*sqrt(2.)*r/n;
	float x = r*sqrt(2.)/n;
	pMod1(p.x, x);
	d = min(d, p.y);
	pR45(p);
	return min(d, vmax(p -vec2(0.5*r/n)));
}

// We can just call Union since stairs are symmetric.
float fOpIntersectionStairs(float a, float b, float r, float n) {
	return -fOpUnionStairs(-a, -b, r, n);
}

float fOpDifferenceStairs(float a, float b, float r, float n) {
	return -fOpUnionStairs(-a, b, r, n);
}

// This produces a cylindical pipe that runs along the intersection.
// No objects remain, only the pipe. This is not a boolean operator.
float fOpPipe(float a, float b, float r) {
	return length(vec2(a, b)) - r;
}


//
// Description : Array and textureless GLSL 2D/3D/4D simplex
//               noise functions.
//      Author : Ian McEwan, Ashima Arts.
//  Maintainer : ijm
//     Lastmod : 20110822 (ijm)
//     License : Copyright (C) 2011 Ashima Arts. All rights reserved.
//               Distributed under the MIT License. See LICENSE file.
//               https://github.com/ashima/webgl-noise
//

vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
     return mod289(((x*34.0)+1.0)*x);
}

vec4 taylorInvSqrt(vec4 r)
{
  return 1.79284291400159 - 0.85373472095314 * r;
}

float snoise(vec3 v)
  {
  const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
  const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

// First corner
  vec3 i  = floor(v + dot(v, C.yyy) );
  vec3 x0 =   v - i + dot(i, C.xxx) ;

// Other corners
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min( g.xyz, l.zxy );
  vec3 i2 = max( g.xyz, l.zxy );

  //   x0 = x0 - 0.0 + 0.0 * C.xxx;
  //   x1 = x0 - i1  + 1.0 * C.xxx;
  //   x2 = x0 - i2  + 2.0 * C.xxx;
  //   x3 = x0 - 1.0 + 3.0 * C.xxx;
  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy; // 2.0*C.x = 1/3 = C.y
  vec3 x3 = x0 - D.yyy;      // -1.0+3.0*C.x = -0.5 = -D.y

// Permutations
  i = mod289(i);
  vec4 p = permute( permute( permute(
             i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0 ))
           + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

// Gradients: 7x7 points over a square, mapped onto an octahedron.
// The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
  float n_ = 0.142857142857; // 1.0/7.0
  vec3  ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);  //  mod(p,7*7)

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

  vec4 x = x_ *ns.x + ns.yyyy;
  vec4 y = y_ *ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4( x.xy, y.xy );
  vec4 b1 = vec4( x.zw, y.zw );

  //vec4 s0 = vec4(lessThan(b0,0.0))*2.0 - 1.0;
  //vec4 s1 = vec4(lessThan(b1,0.0))*2.0 - 1.0;
  vec4 s0 = floor(b0)*2.0 + 1.0;
  vec4 s1 = floor(b1)*2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
  vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

  vec3 p0 = vec3(a0.xy,h.x);
  vec3 p1 = vec3(a0.zw,h.y);
  vec3 p2 = vec3(a1.xy,h.z);
  vec3 p3 = vec3(a1.zw,h.w);

//Normalise gradients
  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

// Mix final noise value
  vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 42.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1),
                                dot(p2,x2), dot(p3,x3) ) );
  }



// Created by inigo quilez - iq/2014
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.

// An edge antialising experiment (not multisampling used)
//
// If slow_antialias is disabled, then only the 4 closest hit points are used for antialising,
// otherwise all found partial-intersections are considered.

#define ANTIALIASING
//#define SLOW_ANTIALIAS

vec2 sincos( float x ) { return vec2( sin(x), cos(x) ); }

vec2 sdSegment( in vec3 p, in vec3 a, in vec3 b )
{
    vec3 pa = p-a, ba = b-a;
	float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
	return vec2( length( pa-ba*h ), h );
}

vec3 opU( vec3 d1, vec3 d2 ) { return (d1.x<d2.x) ? d1 : d2; }

float sdBox( vec3 p, vec3 b )
{
  vec3 d = abs(p) - b;
  return min(max(d.x,max(d.y,d.z)),0.0) +
         length(max(d,0.0));
}

float sdSphere( vec3 p, float s )
{
  return length(p)-s;
}

float sdTorus( vec3 p, vec2 t )
{
  vec2 q = vec2(length(p.xz)-t.x,p.y);
  return length(q)-t.y;
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float lerp(float a, float b, float w)
{
  return a + w*(b-a);
}

float map( vec3 p )
{
    float h;
    float r;
    float c;
    r = 0.5;
    h = fBox(p, vec3(0.2,1.1,0.3));
    c = fCircle(p, 0.3);
    h = abs( tan(p.x + fOpDifferenceRound(h, c,2.8)) / sin(p.x *10.1) * 3.0*PI);
    h = pow(h, 15.0);
    return h;
}

//-------------------------------------------------------


vec3 calcNormal( in vec3 pos, in float dt )
{
    vec2 e = vec2(1.0,-1.0)*dt;
    return normalize( e.xyy*map( pos + e.xyy ) +
					  e.yyx*map( pos + e.yyx ) +
					  e.yxy*map( pos + e.yxy ) +
					  e.xxx*map( pos + e.xxx ) );
}

float calcOcc( in vec3 pos, in vec3 nor )
{
    const float h = 0.15;
	float ao = 0.0;
    for( int i=0; i<8; i++ )
    {
        vec3 dir = sin( float(i)*vec3(1.0,7.13,13.71)+vec3(0.0,2.0,4.0) );
        dir = dir + 2.5*nor*max(0.0,-dot(nor,dir));
        float d = map( pos + h*dir );
        ao += max(0.0,h-d);
    }
    return clamp( 1.0 - 0.7*ao, 0.0, 1.0 );
}

//-------------------------------------------------------
vec3 shade( in float t, in float m, in float v, in vec3 ro, in vec3 rd )
{
    float px = 0.0001;//(2.0/iResolution.y)*(1.0/3.0);
    float eps = px*t;

    vec3  pos = ro + t*rd;
    vec3  nor = calcNormal( pos, eps );
    float occ = calcOcc( pos, nor );

    vec3 col = 0.5 + 0.5*cos( m*vec3(1.4,1.2,1.0) + vec3(0.0,1.0,2.0) );
    col += 0.05*nor;
    col = clamp( col, 0.0, 1.0 );
    col *= 1.0 + 0.5*nor.x;
    col += 0.2*clamp(1.0+dot(rd,nor),0.0,1.0);
    col *= 1.4;
    col *= occ;
    col *= exp( -0.15*t );
    col *= 1.0 - smoothstep( 15.0, 35.0, t );

    return col;
}

//-------------------------------------------------------

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
	vec2 p = (-iResolution.xy+2.0*fragCoord.xy)/iResolution.y;



	vec3 ro = 0.6*vec3(2.0,-3.0, 4.0);
	vec3 ta = 0.5*vec3(0.0, 4.0,-4.0);

    ro.x-=cos(iGlobalTime / 30.) * 2.;
    ta.y-=sin(iGlobalTime / 10.) * 2.;

    float fl = 1.0;
    vec3 ww = normalize( ta - ro);
    vec3 uu = normalize( cross( vec3(1.0,0.0,0.0), ww ) );
    vec3 vv = normalize( cross(ww,uu) );
    vec3 rd = normalize( p.x*uu + p.y*vv + fl*ww );

    float px = (2.0/iResolution.y)*(1.0/fl);

    vec3 col = vec3(0.0);

    //---------------------------------------------
    // raymach loop
    //---------------------------------------------
    const float maxdist = 64.0; // 64.0
	const int maxiteration = 128; //1024; // 256;

    vec3 res = vec3(-1.0);
    float t = 0.0;
    #ifdef ANTIALIASING
    vec3 oh = vec3(0.0);
    mat4 hit = mat4(-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0,-1.0);
    #endif


    for( int i=0; i<maxiteration; i++ )
    {
	    vec3 h = vec3(map( ro + t*rd ), 10.7, 10.);
        float th1 = px*t;
        res = vec3( t, h.yz );
        if( h.x<th1 || t>maxdist ) break;


        #ifdef ANTIALIASING
        float th2 = px*t*3.0;
        if( (h.x<th2) && (h.x>oh.x) )
        {
            float lalp = 1.0 - (h.x-th1)/(th2-th1);
            #ifdef SLOW_ANTIALIAS
             vec3  lcol = shade( t, oh.y, oh.z, ro, rd );
             tmp.xyz += (1.0-tmp.w)*lalp*lcol;
             tmp.w   += (1.0-tmp.w)*lalp;
             if( tmp.w>0.99 ) break;
            #else
             if( hit[0].x<0.0 )
             {
             hit[0] = hit[1]; hit[1] = hit[2]; hit[2] = hit[3]; hit[3] = vec4( t, oh.yz, lalp );
             }
            #endif
        }
        oh = h;
        #endif

        t += min( h.x, 0.5 )*0.5;
    }

    if( t < maxdist )
        col = shade( res.x, res.y, res.z, ro, rd );

    #ifdef ANTIALIASING
    #ifdef SLOW_ANTIALIAS
	col = mix( col, tmp.xyz/(0.001+tmp.w), tmp.w );
    #else
    for( int i=0; i<4; i++ ) // blend back to front
    if( hit[3-i].x>0.0 )
        col = mix( col, shade( hit[3-i].x, hit[3-i].y, hit[3-i].z, ro, rd ), hit[3-i].w );
    #endif
    #endif

    //---------------------------------------------

    col = pow( col, vec3(0.3,0.24,0.1) );

    col = col / 2. + col / 1.3 * vec3(pow(col.r * col.g * col.b * 1.3, 1.5));




    //vec2 q = fragCoord.xy/iResolution.xy;
    //col /= pow(16.0*q.x*q.y*(1.0-q.x)*(1.0-q.y),0.1);


    //col += 0.015;
    //col *= 1.4;
//    col = clamp(col, 0., 1.);

	fragColor = vec4( col, 1.0 );
}
