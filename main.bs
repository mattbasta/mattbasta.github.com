(function(runner) {
    console.log(runner.toString());
    runner();
})(function() {
'use strict';

var COUNT = 250;
var DOUBLES = 8;
var TEXTURE_SIZE = 30;
var HUE_DAMPENER = 200;
var ALIGNMENT_THRESHOLD = 30;

var camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 1, 10000);
camera.position.z = 1000;

var to_x = 0;
var to_y = 0;

var orbCache = {};
function generateOrb(alignment) {
    alignment = Math.pow(alignment / HUE_DAMPENER, 3) | 0;
    var haze = Math.min(Math.max(4000 / alignment, 10), 35) | 0;
    var haze_dark = Math.min(Math.max(3000 / alignment / 3, 5), 15) | 0;
    alignment = Math.min(Math.max(alignment + 190, 190), 255) | 0;
    var cacheValue = alignment + ':' + haze + ':' + haze_dark;
    if (cacheValue in orbCache) {
        return orbCache[cacheValue];
    }

    var canvas = document.createElement('canvas');
    canvas.width = canvas.height = TEXTURE_SIZE;

    var context = canvas.getContext('2d');
    context.clearRect(0, 0, TEXTURE_SIZE, TEXTURE_SIZE);
    var gradient = context.createRadialGradient(TEXTURE_SIZE / 2, TEXTURE_SIZE / 2, 0, TEXTURE_SIZE / 2, TEXTURE_SIZE / 2, TEXTURE_SIZE / 2);
    gradient.addColorStop(0, 'hsla(255,100%,100%,1)');
    gradient.addColorStop(Math.random() * 0.075 + 0.15, 'hsla(' + alignment + ',80%,' + haze + '%,1)');;
    gradient.addColorStop(Math.random() * 0.075 + 0.35, 'hsla(' + alignment + ',60%,' + haze_dark + '%,1)');
    gradient.addColorStop(1, 'rgba(0,0,0,1)');

    context.fillStyle = gradient;
    context.fillRect(0, 0, TEXTURE_SIZE, TEXTURE_SIZE);

    orbCache[cacheValue] = canvas;
    return canvas;
}

var scene = new THREE.Scene();
var scene_wrap = new THREE.Object3D();

function sphere(index) {
    this.index = index;
    this.texture = new THREE.Texture(generateOrb(0));
    this.texture.needsUpdate = true;
    this.material = new THREE.SpriteMaterial({
        map: this.texture,
        blending: THREE.AdditiveBlending
    });
    this.particle = new THREE.Sprite(this.material);

    this.last_alignment = this.alignment = 0;
    this.setMass(15);
    this.setPosition(0, 0, 0);
}

sphere.prototype.setPosition = function(x, y, z) {
    this.particle.position.set(x, y, z);
};

sphere.prototype.setMass = function(mass) {
    this.mass = mass;
    var scale = Math.pow(mass * 2, 1.2);
    this.particle.scale.set(scale, scale, 1);
};

sphere.prototype.setAlignment = function(alignment) {
    // return;
    this.alignment = alignment;
    if (Math.abs(this.alignment - this.last_alignment) > ALIGNMENT_THRESHOLD) {
        this.last_alignment = alignment;
        this.texture.image = generateOrb(alignment, this.texture.image);
        this.texture.needsUpdate = true;
    }
};

var spheres = [];

for (var i = 0; i < COUNT; i++) {
    var s = new sphere(i)
    spheres.push(s);
    scene_wrap.add(s.particle);
}
scene.add(scene_wrap);

// var test_geom = new THREE.Geometry();
// test_geom.vertices.push( new THREE.Vector3( -100,  100, 0 ) );
// test_geom.vertices.push( new THREE.Vector3( 100, -100, 0 ) );
// var testline = new THREE.Line(test_geom);
// scene_wrap.add(testline);

// var renderer = new THREE.CanvasRenderer();
var renderer = new THREE.WebGLRenderer({antialias: false, alpha: false});
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

function animate() {
    (requestAnimationFrame || webkitRequestAnimationFrame)(animate);
    renderer.render(scene, camera);
    scene_wrap.position.set(
        (to_x + scene_wrap.position.x * 5) / 6 | 0,
        (to_y + scene_wrap.position.y * 5) / 6 | 0,
        0
    );
}
animate();
console.log('Started renderer');

window.addEventListener('mousemove', function(e) {
    to_x = (e.clientX - window.innerWidth / 2) * 0.2 | 0;
    to_y = (window.innerHeight / 2 - e.clientY) * 0.2 | 0;
}, false);

function workerBase(count, DOUBLES) {
    var self = this;
    var GRAVITY = 6.673848;
    var SOFTENING = 0.001;
    var DISTANCE_TUG = 1000000;
    var BOUNCE_SOFTENING = 0.5;

    var buffer = new ArrayBuffer(Float32Array.BYTES_PER_ELEMENT * count * DOUBLES);
    var data = new Float32Array(buffer);

    this.onmessage = function(e) {
        buffer = e.data;
        data = new Float32Array(buffer);
        setTimeout(work, 20);
    };

    // Prepopulate data for each orb.
    var offset = 0;
    for (var i = 0; i < count; i++) {
        offset = i * DOUBLES;
        // Position
        data[offset + 0] = Math.random() * 2000 - 1000;
        data[offset + 1] = Math.random() * 2000 - 1000;
        data[offset + 2] = Math.random() * 2000 - 1250;
        // Velocity
        data[offset + 3] = Math.random() * 16 - 8;
        data[offset + 4] = Math.random() * 16 - 8;
        data[offset + 5] = Math.random() * 16 - 8;
        // Mass
        data[offset + 6] = Math.random() * 15 + 15.0;
        // Alignment
        data[offset + 7] = 0;
    }

    function work() {
        var offset = 0;
        var temp_offset = 0;
        var temp_dist = 0.0;
        var vx = 0, vy = 0, vz = 0;
        var temp_dx = 0, temp_dy = 0, temp_dz = 0;
        var collided = new Array(count);
        var total_dist = 0;
        for (var i = 0; i < count; i++) {
            offset = i * DOUBLES;

            vx = 0;
            vy = 0;
            vz = 0;
            total_dist = 0;
            for (var j = 0; j < count; j++) {
                if (j === i) continue;
                if (collided[j]) continue;

                temp_offset = j * DOUBLES;
                temp_dx = data[offset + 0] - data[temp_offset + 0];
                temp_dy = data[offset + 1] - data[temp_offset + 1];
                temp_dz = data[offset + 2] - data[temp_offset + 2];
                temp_dist = Math.sqrt(
                    temp_dx * temp_dx + temp_dy * temp_dy + temp_dz * temp_dz
                );
                total_dist += temp_dist;
                if (temp_dist < data[offset + 6] + data[temp_offset + 6]) {
                    // console.log('Collision between' + i + ' and ' + j);
                    // Simulate an inelastic collision.
                    vx = data[temp_offset + 3] * BOUNCE_SOFTENING;
                    vy = data[temp_offset + 4] * BOUNCE_SOFTENING;
                    vz = data[temp_offset + 5] * BOUNCE_SOFTENING;
                    data[temp_offset + 3] = data[offset + 3] * BOUNCE_SOFTENING;
                    data[temp_offset + 4] = data[offset + 4] * BOUNCE_SOFTENING;
                    data[temp_offset + 5] = data[offset + 5] * BOUNCE_SOFTENING;
                    collided[i] = true;
                    break;
                }
                vx -= SOFTENING * temp_dx / temp_dist;
                vy -= SOFTENING * temp_dy / temp_dist;
                vz -= SOFTENING * temp_dz / temp_dist;
            }

            // All are drawn to the origin.
            vx -= data[offset + 0] / (DISTANCE_TUG / Math.min(Math.abs(data[offset + 0]), 10000));
            vy -= data[offset + 1] / (DISTANCE_TUG / Math.min(Math.abs(data[offset + 1]), 10000));
            vz -= data[offset + 2] / (DISTANCE_TUG / Math.min(Math.abs(data[offset + 2]), 10000));

            data[offset + 3] += vx;
            data[offset + 4] += vy;
            data[offset + 5] += vz;

            data[offset + 0] += data[offset + 3];
            data[offset + 1] += data[offset + 4];
            data[offset + 2] += data[offset + 5];

            data[offset + 7] = total_dist / count;

            if (data[offset + 2] > 750) {
                data[offset + 2] = 750;
                data[offset + 5] = -1 * Math.abs(data[offset + 5]);
                if (Math.abs(data[offset + 0]) < 300 &&
                    Math.abs(data[offset + 1]) < 300) {
                    self.postMessage('thunk');
                }
            }

        }
        self.postMessage(buffer, [buffer]);
    }
    work();
}
var worker = new Worker(
    (URL || webkitURL).createObjectURL(
        new Blob(['(' + workerBase.toString() + ').call(self, ' + COUNT + ', ' + DOUBLES + ')'], {type: 'text/javascript'})
    )
);
worker.onmessage = function(e) {
    if (e.data === 'thunk') {
        console.log('thunk');
        return;
    }
    var sphere;
    var data = new Float32Array(e.data);
    for (var i = 0; i < COUNT; i++) {
        spheres[i].setPosition(
            data[i * DOUBLES + 0],
            data[i * DOUBLES + 1],
            data[i * DOUBLES + 2]
        );
        spheres[i].setMass(data[i * DOUBLES + 6]);
        spheres[i].setAlignment(data[i * DOUBLES + 7]);
    }
    worker.postMessage(e.data, [e.data]);
};

});
