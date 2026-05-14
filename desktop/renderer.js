const widget = document.getElementById('widget');
const label = document.getElementById('label');
const viz = document.getElementById('viz');
const vizCtx = viz.getContext('2d');

const VIZ_SIZE = 36;
const SEGMENTS = 22;
const INNER_R = 8.5;
const MAX_BAR = 8;

(function initCanvas() {
  const dpr = window.devicePixelRatio || 1;
  viz.width = VIZ_SIZE * dpr;
  viz.height = VIZ_SIZE * dpr;
  viz.style.width = VIZ_SIZE + 'px';
  viz.style.height = VIZ_SIZE + 'px';
  vizCtx.scale(dpr, dpr);
})();

let state = 'idle';
let config = null;
let mediaRecorder = null;
let mediaStream = null;
let chunks = [];

let audioCtx = null;
let analyser = null;
let freqData = null;
let rafId = null;
let rotation = 0;

const STATE_CLASSES = ['state-idle', 'state-recording', 'state-processing', 'state-done', 'state-error'];
function setState(next, text) {
  state = next;
  widget.classList.remove(...STATE_CLASSES);
  widget.classList.add(`state-${next}`);
  if (text) label.textContent = text;
}

let drag = null;
let justDragged = false;
const DRAG_THRESHOLD = 4;

async function init() {
  config = await window.api.getConfig();
  window.api.onHotkeyToggle(() => toggleHotkey());
  setState('idle', 'idle');

  widget.addEventListener('mousedown', async (e) => {
    if (e.button !== 0) return;
    const [wx, wy] = await window.api.getWidgetPosition();
    drag = {
      startScreenX: e.screenX,
      startScreenY: e.screenY,
      startWinX: wx,
      startWinY: wy,
      moved: false
    };
  });

  window.addEventListener('mousemove', (e) => {
    if (!drag) return;
    const dx = e.screenX - drag.startScreenX;
    const dy = e.screenY - drag.startScreenY;
    if (!drag.moved) {
      if (Math.abs(dx) < DRAG_THRESHOLD && Math.abs(dy) < DRAG_THRESHOLD) return;
      drag.moved = true;
      widget.classList.add('dragging');
    }
    window.api.setWidgetPosition(drag.startWinX + dx, drag.startWinY + dy);
  });

  window.addEventListener('mouseup', () => {
    if (drag && drag.moved) {
      justDragged = true;
      widget.classList.remove('dragging');
      setTimeout(() => { justDragged = false; }, 150);
    }
    drag = null;
  });

  widget.addEventListener('click', () => {
    if (justDragged) return;
    if (state === 'recording') stopRecording();
  });
  widget.addEventListener('dblclick', () => {
    if (justDragged) return;
    if (state === 'idle' || state === 'done' || state === 'error') startRecording();
  });
  widget.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    window.api.showWidgetMenu();
  });
}

function toggleHotkey() {
  if (state === 'recording') {
    stopRecording();
  } else if (state === 'idle' || state === 'done' || state === 'error') {
    startRecording();
  }
}

let recordingStartedAt = 0;
const MIN_RECORDING_MS = 400;

async function startRecording() {
  try {
    config = await window.api.getConfig();
    if (!config.groqApiKey) {
      setState('error', 'no key');
      window.api.openSettings();
      setTimeout(() => setState('idle', 'idle'), 1800);
      return;
    }
    mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true
      }
    });
    chunks = [];
    mediaRecorder = new MediaRecorder(mediaStream, { mimeType: 'audio/webm' });
    mediaRecorder.ondataavailable = (e) => { if (e.data.size > 0) chunks.push(e.data); };
    mediaRecorder.onstop = onRecordingStopped;
    mediaRecorder.start();
    recordingStartedAt = Date.now();
    startViz();
    setState('recording', 'rec');
  } catch (e) {
    console.error('startRecording error:', e);
    setState('error', 'mic?');
    setTimeout(() => setState('idle', 'idle'), 2000);
  }
}

async function stopRecording() {
  if (!mediaRecorder) return;
  const elapsed = Date.now() - recordingStartedAt;
  if (elapsed < MIN_RECORDING_MS) return;
  setState('processing', 'thinking');
  mediaRecorder.stop();
}

function stopStream() {
  if (mediaStream) {
    mediaStream.getTracks().forEach((t) => t.stop());
    mediaStream = null;
  }
  stopViz();
}

function startViz() {
  audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  const source = audioCtx.createMediaStreamSource(mediaStream);
  analyser = audioCtx.createAnalyser();
  analyser.fftSize = 128;
  analyser.smoothingTimeConstant = 0.72;
  source.connect(analyser);
  freqData = new Uint8Array(analyser.frequencyBinCount);
  rotation = 0;
  drawFrame();
}

function stopViz() {
  if (rafId) cancelAnimationFrame(rafId);
  rafId = null;
  if (audioCtx) { audioCtx.close().catch(() => {}); audioCtx = null; }
  analyser = null;
  freqData = null;
  vizCtx.clearRect(0, 0, VIZ_SIZE, VIZ_SIZE);
}

function drawFrame() {
  if (!analyser) return;
  analyser.getByteFrequencyData(freqData);

  const cx = VIZ_SIZE / 2;
  const cy = VIZ_SIZE / 2;
  vizCtx.clearRect(0, 0, VIZ_SIZE, VIZ_SIZE);

  let sum = 0;
  for (let i = 0; i < freqData.length; i++) sum += freqData[i];
  const overall = sum / (freqData.length * 255);

  rotation += 0.012 + overall * 0.05;

  vizCtx.save();
  vizCtx.translate(cx, cy);
  vizCtx.rotate(rotation);

  vizCtx.beginPath();
  vizCtx.arc(0, 0, INNER_R - 1, 0, Math.PI * 2);
  vizCtx.fillStyle = `rgba(239, 68, 68, ${0.18 + overall * 0.5})`;
  vizCtx.fill();

  vizCtx.lineCap = 'round';
  for (let i = 0; i < SEGMENTS; i++) {
    const bin = Math.min(freqData.length - 1, Math.floor((i / SEGMENTS) * freqData.length * 0.7));
    const amp = freqData[bin] / 255;
    const len = INNER_R + amp * MAX_BAR + 0.5;
    const angle = (i / SEGMENTS) * Math.PI * 2;
    const x1 = Math.cos(angle) * INNER_R;
    const y1 = Math.sin(angle) * INNER_R;
    const x2 = Math.cos(angle) * len;
    const y2 = Math.sin(angle) * len;
    vizCtx.strokeStyle = `rgba(252, 165, 165, ${0.55 + amp * 0.45})`;
    vizCtx.lineWidth = 1.6;
    vizCtx.beginPath();
    vizCtx.moveTo(x1, y1);
    vizCtx.lineTo(x2, y2);
    vizCtx.stroke();
  }

  vizCtx.restore();
  rafId = requestAnimationFrame(drawFrame);
}

async function onRecordingStopped() {
  try {
    const blob = new Blob(chunks, { type: 'audio/webm' });
    stopStream();

    if (blob.size < 1000) {
      setState('error', 'too short');
      setTimeout(() => setState('idle', 'idle'), 1500);
      return;
    }

    const raw = (await window.openwispr.transcribeBlob(blob, config)).trim();
    if (!raw) {
      setState('error', 'empty');
      setTimeout(() => setState('idle', 'idle'), 1500);
      return;
    }

    let final = raw;
    if (config.cleanupEnabled) {
      try {
        final = await window.openwispr.cleanupText(raw, config);
      } catch (e) {
        console.error('Cleanup failed, using raw:', e);
      }
    }

    try {
      await window.api.transcripts.save({ raw, text: final });
    } catch (e) {
      console.error('Save transcript failed:', e);
    }

    if (config.pasteOnFinish) {
      await window.api.pasteText(final);
    } else {
      await window.api.copyText(final);
    }

    setState('done', 'pasted');
    setTimeout(() => setState('idle', 'idle'), 1200);
  } catch (e) {
    console.error('Processing error:', e);
    setState('error', 'err');
    setTimeout(() => setState('idle', 'idle'), 2000);
  }
}

init();
