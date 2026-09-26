'use strict';

const profiles = Object.freeze({
  sysadmin: { name: 'Sysadmin', color: '#ffbc66', rgb: '255, 188, 102', scene: 'AMBER SENTINEL', speed: 0.5, description: 'A steady amber horizon for deliberate control.' },
  developer: { name: 'Developer', color: '#6fe8fa', rgb: '111, 232, 250', scene: 'ION FIELD', speed: 0.8, description: 'A clear signal for building, inspecting and connecting.' },
  studio: { name: 'Studio', color: '#d8a0fa', rgb: '216, 160, 250', scene: 'VIOLET RESONANCE', speed: 0.6, description: 'A softer rhythm for sound, light and original ideas.' },
  gamer: { name: 'Gamer', color: '#ff7e8b', rgb: '255, 126, 139', scene: 'EMBER VELOCITY', speed: 1.2, description: 'Warm light and a livelier pulse for the next world.' },
  core: { name: 'Core', color: '#ace7b4', rgb: '172, 231, 180', scene: 'QUIET ORBIT', speed: 0.35, description: 'An open, quiet space with room to concentrate.' },
  'ai-server': { name: 'AI/Server', color: '#93b7ff', rgb: '147, 183, 255', scene: 'BLUE CONSTELLATION', speed: 0.7, description: 'A measured constellation for agents, models and fleets.' },
});

const canvas = document.querySelector('#atmosphere');
const context = canvas.getContext('2d');
const profileButtons = [...document.querySelectorAll('.profile')];
const motionToggle = document.querySelector('#reduced-motion');
const pauseButton = document.querySelector('#pause');
const intensityInput = document.querySelector('#intensity');
const motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');
const particles = Array.from({ length: 64 }, (_, index) => ({
  // Deterministic positions make paused profile comparisons repeatable.
  x: ((index * 37 + 11) % 101) / 101,
  y: ((index * 53 + 7) % 97) / 97,
  radius: 0.5 + (index % 4) * 0.35,
  drift: 0.7 + (index % 7) * 0.1,
}));

let selected = 'developer';
let paused = false;
let motionOverridden = false;
let intensity = 0.65;
let width = 1;
let height = 1;
let time = 0;
let previousTime = null;
let animation = null;
motionToggle.checked = motionPreference.matches;

function isMoving() {
  return !paused && !motionToggle.checked && !document.hidden;
}

function updateStatus() {
  document.body.dataset.reducedMotion = String(motionToggle.checked);
  pauseButton.disabled = motionToggle.checked;
  pauseButton.setAttribute('aria-pressed', String(paused));
  pauseButton.textContent = paused ? 'Resume motion' : 'Pause motion';
  const state = motionToggle.checked ? 'Reduced motion is on.' : paused ? 'Motion is paused.' : 'Motion is running.';
  document.querySelector('#scene-status').textContent = `${profiles[selected].name} selected. ${state}`;
}

function draw() {
  if (!context) return;
  const profile = profiles[selected];
  const centerX = width * 0.76;
  const centerY = height * 0.56;
  const radius = Math.min(width * 0.2, height * 0.3);
  const phase = time * 0.22;
  context.clearRect(0, 0, width, height);

  const halo = context.createRadialGradient(centerX, centerY, 0, centerX, centerY, radius * 1.75);
  halo.addColorStop(0, `rgba(${profile.rgb}, ${0.12 * intensity})`);
  halo.addColorStop(1, `rgba(${profile.rgb}, 0)`);
  context.fillStyle = halo;
  context.fillRect(0, 0, width, height);

  context.save();
  context.translate(centerX, centerY);
  context.strokeStyle = `rgba(${profile.rgb}, ${0.28 * intensity})`;
  context.lineWidth = 1;
  for (let ring = 0; ring < 3; ring += 1) {
    context.beginPath();
    context.ellipse(0, 0, radius * (0.72 + ring * 0.2), radius * (0.72 + ring * 0.2), 0, phase + ring * 1.9, phase + ring * 1.9 + Math.PI * 1.55);
    context.stroke();
  }
  for (let index = 0; index < 36; index += 1) {
    const angle = index * Math.PI / 18;
    const outer = radius * 1.25;
    const inner = outer - (index % 3 === 0 ? 8 : 3);
    context.beginPath();
    context.moveTo(Math.cos(angle) * inner, Math.sin(angle) * inner);
    context.lineTo(Math.cos(angle) * outer, Math.sin(angle) * outer);
    context.stroke();
  }

  // An original ether-blade motif: a light core enclosed by two asymmetric rails.
  context.rotate(-0.13 + Math.sin(time * 0.15) * 0.015);
  const bladeHeight = radius * 1.7;
  context.shadowColor = profile.color;
  context.shadowBlur = 20 * intensity;
  context.strokeStyle = `rgba(${profile.rgb}, ${0.5 + intensity * 0.4})`;
  context.lineWidth = 2;
  context.beginPath();
  context.moveTo(-11, radius * 0.55);
  context.lineTo(-15, -radius * 0.5);
  context.lineTo(0, -bladeHeight);
  context.lineTo(18, -radius * 0.2);
  context.lineTo(10, radius * 0.55);
  context.stroke();
  context.fillStyle = `rgba(${profile.rgb}, ${intensity * 0.13})`;
  context.fill();
  context.strokeStyle = '#eaffff';
  context.lineWidth = 1.5;
  context.beginPath();
  context.moveTo(0, radius * 0.46);
  context.lineTo(0, -bladeHeight + 20);
  context.stroke();
  context.shadowBlur = 9 * intensity;
  context.strokeStyle = profile.color;
  context.lineWidth = 3;
  context.beginPath();
  context.arc(0, radius * 0.6, 17, 0, Math.PI * 2);
  context.stroke();
  context.beginPath();
  context.moveTo(0, radius * 0.6 + 18);
  context.lineTo(0, radius * 1.02);
  context.stroke();
  context.restore();

  particles.forEach((particle, index) => {
    const travel = time * 0.028 * particle.drift;
    const x = width * (0.48 + particle.x * 0.52) + Math.sin(time * 0.35 + index) * 7;
    const y = height * (1 - ((particle.y + travel) % 1));
    const alpha = (0.18 + particle.x * 0.48) * intensity;
    context.fillStyle = `rgba(${profile.rgb}, ${alpha})`;
    context.beginPath();
    context.arc(x, y, particle.radius, 0, Math.PI * 2);
    context.fill();
  });
}

function frame(timestamp) {
  animation = null;
  if (!isMoving()) {
    previousTime = null;
    return;
  }
  if (previousTime !== null) {
    time += Math.min((timestamp - previousTime) / 1000, 0.05) * profiles[selected].speed;
  }
  previousTime = timestamp;
  draw();
  animation = window.requestAnimationFrame(frame);
}

function refresh() {
  if (animation !== null) window.cancelAnimationFrame(animation);
  animation = null;
  previousTime = null;
  draw();
  if (isMoving() && context) animation = window.requestAnimationFrame(frame);
}

function resize() {
  const bounds = canvas.getBoundingClientRect();
  const scale = Math.min(window.devicePixelRatio || 1, 2);
  width = Math.max(1, bounds.width);
  height = Math.max(1, bounds.height);
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  if (context) context.setTransform(scale, 0, 0, scale, 0, 0);
  refresh();
}

profileButtons.forEach((button) => button.addEventListener('click', () => {
  const next = button.dataset.profile;
  if (!Object.hasOwn(profiles, next)) return;
  selected = next;
  const profile = profiles[selected];
  document.body.dataset.profile = selected;
  document.documentElement.style.setProperty('--accent', profile.color);
  document.documentElement.style.setProperty('--accent-rgb', profile.rgb);
  document.querySelector('#profile-title').textContent = profile.name;
  document.querySelector('#profile-description').textContent = profile.description;
  document.querySelector('#scene-name').textContent = profile.scene;
  profileButtons.forEach((item) => item.setAttribute('aria-pressed', String(item === button)));
  updateStatus();
  refresh();
}));

intensityInput.addEventListener('input', () => {
  intensity = Number(intensityInput.value) / 100;
  document.querySelector('#intensity-value').textContent = `${intensityInput.value}%`;
  if (!isMoving()) draw();
});

pauseButton.addEventListener('click', () => {
  paused = !paused;
  updateStatus();
  refresh();
});

motionToggle.addEventListener('change', () => {
  motionOverridden = true;
  updateStatus();
  refresh();
});

motionPreference.addEventListener('change', (event) => {
  if (motionOverridden) return;
  motionToggle.checked = event.matches;
  updateStatus();
  refresh();
});

document.addEventListener('visibilitychange', refresh);
new ResizeObserver(resize).observe(canvas);
updateStatus();
resize();
