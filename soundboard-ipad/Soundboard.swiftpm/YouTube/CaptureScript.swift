enum CaptureScript {
    /// Injected into every YouTube page. It routes the page's <video> through
    /// Web Audio, records the samples between two timestamps and streams them
    /// to the app as 16-bit PCM through the "soundboard" message handler.
    static let source = #"""
// BEGIN CAPTURE SCRIPT
(() => {
  if (window.__sb) return;

  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.soundboard;
  const post = (msg) => { if (handler) handler.postMessage(msg); };

  const getVideo = () => document.querySelector('video.html5-main-video') || document.querySelector('video');
  const adShowing = () => {
    const player = document.querySelector('#movie_player');
    return !!(player && player.classList.contains('ad-showing'));
  };
  const videoTitle = () => {
    const el = document.querySelector('h1.ytd-watch-metadata yt-formatted-string, h1.title, #title h1, .slim-video-information-title');
    return (el && el.textContent.trim()) || document.title.replace(/ - YouTube$/, '');
  };

  let ctx = null;
  const taps = new WeakMap();
  let onBuffer = null; // set while a capture is running

  // Once a video is routed through Web Audio it stays that way, so the tap
  // is created lazily on the first capture and reused afterwards.
  function tap(video) {
    if (taps.has(video)) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    ctx = ctx || new AC();
    const source = ctx.createMediaElementSource(video);
    const processor = ctx.createScriptProcessor(2048, 2, 2);
    const silent = ctx.createGain();
    silent.gain.value = 0;
    source.connect(ctx.destination); // keep the video audible
    source.connect(processor);
    processor.connect(silent);
    silent.connect(ctx.destination);
    processor.onaudioprocess = (e) => { if (onBuffer) onBuffer(e.inputBuffer, video); };
    video.addEventListener('play', () => { ctx.resume(); });
    taps.set(video, processor);
  }

  function toBase64(bytes) {
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(binary);
  }

  let stopPreview = null;
  let cancelCapture = null;

  window.__sb = {
    state() {
      const v = getVideo();
      if (!v) return JSON.stringify({ hasVideo: false, url: location.href });
      return JSON.stringify({
        hasVideo: true,
        currentTime: v.currentTime,
        duration: isFinite(v.duration) ? v.duration : 0,
        paused: v.paused,
        ad: adShowing(),
        title: videoTitle(),
        url: location.href,
      });
    },

    // Plays [start, end] once so the user can check their selection.
    preview(start, end) {
      const v = getVideo();
      if (!v) return 'no-video';
      if (stopPreview) stopPreview();
      const onTime = () => { if (v.currentTime >= end) { v.pause(); if (stopPreview) stopPreview(); } };
      const onPause = () => { if (stopPreview) stopPreview(); };
      stopPreview = () => {
        v.removeEventListener('timeupdate', onTime);
        v.removeEventListener('pause', onPause);
        stopPreview = null;
      };
      v.currentTime = start;
      v.play().then(() => {
        if (!stopPreview) return;
        v.addEventListener('timeupdate', onTime);
        v.addEventListener('pause', onPause);
      }).catch(() => { if (stopPreview) stopPreview(); });
      return 'ok';
    },

    cancel() {
      if (cancelCapture) cancelCapture('Capture cancelled.');
      return 'ok';
    },

    capture(start, end) {
      run(start, end).catch((err) => post({ type: 'error', message: String((err && err.message) || err) }));
      return 'ok';
    },
  };

  async function run(start, end) {
    const video = getVideo();
    if (!video) throw new Error('Open a YouTube video first.');
    if (adShowing()) throw new Error('An ad is playing. Wait for it to finish, then try again.');
    if (!(end > start)) throw new Error('The end time must be after the start time.');
    if (cancelCapture) throw new Error('A capture is already running.');
    if (stopPreview) stopPreview();

    tap(video);
    try { await ctx.resume(); } catch (e) { /* checked by the watchdog below */ }

    const savedRate = video.playbackRate;
    video.pause();
    video.playbackRate = 1;
    const seekTarget = Math.max(0, start - 0.4);
    const seeked = new Promise((resolve) => video.addEventListener('seeked', resolve, { once: true }));
    video.currentTime = seekTarget;
    await Promise.race([seeked, new Promise((resolve) => setTimeout(resolve, 3000))]);

    const sampleRate = ctx.sampleRate;
    let pending = [];
    let pendingLength = 0;
    let frames = 0;
    let peak = 0;
    let buffers = 0;
    let clock = null; // media time of the next buffer's first sample
    let watchdog = null;

    const flush = () => {
      if (!pendingLength) return;
      const all = new Int16Array(pendingLength);
      let offset = 0;
      for (const part of pending) { all.set(part, offset); offset += part.length; }
      pending = [];
      pendingLength = 0;
      post({ type: 'chunk', data: toBase64(new Uint8Array(all.buffer)) });
    };

    return new Promise((resolve, reject) => {
      let finished = false;
      const finish = (error) => {
        if (finished) return;
        finished = true;
        onBuffer = null;
        cancelCapture = null;
        clearInterval(watchdog);
        video.pause();
        video.playbackRate = savedRate;
        if (error) return reject(new Error(error));
        flush();
        if (!frames) return reject(new Error('No audio was captured.'));
        if (peak < 0.0005) {
          return reject(new Error('Only silence was captured. This video\'s audio may be blocked from capture. Try importing a screen recording instead.'));
        }
        post({ type: 'done', sampleRate, channels: 2, title: videoTitle(), url: location.href, start, end });
        resolve();
      };
      cancelCapture = finish;

      onBuffer = (buffer, v) => {
        buffers++;
        if (adShowing()) return finish('An ad interrupted the capture. Try again after it ends.');
        const n = buffer.length;
        if (clock === null) {
          // Anchor once playback has really started; after that, advance by
          // exact sample counts so the timeline has no gaps or overlaps.
          if (v.paused || v.currentTime <= seekTarget + 0.01) return;
          clock = v.currentTime - n / sampleRate;
        }
        const left = buffer.getChannelData(0);
        const right = buffer.numberOfChannels > 1 ? buffer.getChannelData(1) : left;
        const out = new Int16Array(n * 2);
        let k = 0;
        for (let i = 0; i < n; i++) {
          const t = clock + i / sampleRate;
          if (t < start || t >= end) continue;
          const l = Math.max(-1, Math.min(1, left[i]));
          const r = Math.max(-1, Math.min(1, right[i]));
          peak = Math.max(peak, Math.abs(l), Math.abs(r));
          out[k++] = l < 0 ? l * 0x8000 : l * 0x7fff;
          out[k++] = r < 0 ? r * 0x8000 : r * 0x7fff;
        }
        clock += n / sampleRate;
        if (k) {
          pending.push(out.subarray(0, k));
          pendingLength += k;
          frames += k / 2;
        }
        if (pendingLength >= sampleRate) flush(); // about every half second
        post({ type: 'progress', time: clock, fraction: Math.max(0, Math.min(1, (clock - start) / (end - start))) });
        if (clock >= end || v.ended) finish();
      };

      const startedAt = Date.now();
      watchdog = setInterval(() => {
        const elapsed = Date.now() - startedAt;
        if (!buffers && elapsed > 3000) {
          finish('Audio capture didn\'t start. Tap play on the video once, then try again.');
        } else if (elapsed > (end - start + 20) * 1000) {
          finish('The capture timed out. Check your connection and try again.');
        } else if (video.paused) {
          video.play().catch(() => {});
        }
      }, 500);

      video.play().catch((e) => finish('Couldn\'t start playback: ' + e.message));
    });
  }
})();
// END CAPTURE SCRIPT
"""#
}
