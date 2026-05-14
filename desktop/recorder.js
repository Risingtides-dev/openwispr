const GROQ_BASE = 'https://api.groq.com/openai/v1';

async function transcribeBlob(blob, config) {
  const form = new FormData();
  form.append('file', blob, 'audio.webm');
  form.append('model', config.transcribeModel || 'whisper-large-v3-turbo');
  form.append('response_format', 'text');
  form.append('temperature', '0');
  if (config.vocabulary && config.vocabulary.trim()) {
    form.append('prompt', `Glossary of terms that may appear: ${config.vocabulary.trim()}.`);
  }
  const res = await fetch(`${GROQ_BASE}/audio/transcriptions`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${config.groqApiKey}` },
    body: form
  });
  if (!res.ok) throw new Error(`Transcribe ${res.status}: ${await res.text()}`);
  return await res.text();
}

async function cleanupText(text, config) {
  const sys = (config.cleanupPrompt || '') + (
    config.vocabulary && config.vocabulary.trim()
      ? `\n\nKNOWN VOCABULARY — preserve these exact spellings and fix obvious mistranscriptions to match them: ${config.vocabulary.trim()}`
      : ''
  );
  const res = await fetch(`${GROQ_BASE}/chat/completions`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${config.groqApiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: config.cleanupModel || 'openai/gpt-oss-20b',
      temperature: 0.1,
      messages: [
        { role: 'system', content: sys },
        { role: 'user', content: `<transcript>${text}</transcript>` }
      ]
    })
  });
  if (!res.ok) throw new Error(`Cleanup ${res.status}: ${await res.text()}`);
  const data = await res.json();
  let out = data.choices?.[0]?.message?.content?.trim() || text;
  return out.replace(/^<transcript>\s*/i, '').replace(/\s*<\/transcript>$/i, '').trim();
}

window.openwispr = { transcribeBlob, cleanupText };
