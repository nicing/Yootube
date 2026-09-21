// Player appearance adapted from the user-provided Eagle clip viewer.
// Video.js continues to own sources, buffering, captions and playback.
(() => {
"use strict";
const englishStrings = {
    '本地缓存':'Local cache', '播放':'Play', '视频进度':'Video progress', '静音':'Mute',
    '开启字幕':'Turn on captions', '影院模式':'Theater mode', '更多':'More', '播放设置':'Playback settings',
    '直播':'Live', '暂停':'Pause', '取消静音':'Unmute', '关闭字幕':'Turn off captions',
    '当前视频没有字幕':'No captions are available', '退出影院模式 · Esc':'Exit theater mode · Esc',
    '暂时无法播放，请再次点击播放或重试加载。':'Playback is temporarily unavailable. Click play again or retry.',
    '‹ 返回':'‹ Back', '自动':'Auto', '字幕':'Captions', '音轨':'Audio track', '播放速度':'Playback speed',
    '退出画中画':'Exit Picture in Picture', '画中画':'Picture in Picture',
    '正在准备画中画…':'Preparing Picture in Picture…',
    '当前视频暂时无法进入画中画。':'This video cannot enter Picture in Picture right now.',
    '当前播放环境不支持画中画':'Picture in Picture is unavailable in this playback environment',
    '清晰度':'Quality'
};
const tr = source => window.yootubeLanguage === 'en' ? (englishStrings[source] || source) : source;
let activateMenuButton = null;
let menuPointerID = null;
let suppressMenuPointerClick = false;
let menuPointerResetTimer = null;
function clearMenuPointerSuppression() {
    menuPointerID = null;
    suppressMenuPointerClick = false;
    if (menuPointerResetTimer !== null) clearTimeout(menuPointerResetTimer);
    menuPointerResetTimer = null;
}
window.addEventListener('pointerdown', e => {
    const target = e.target instanceof Element ? e.target : null;
    const button = e.button === 0 ? target?.closest('.video-player__menu-button') : null;
    if (!button || !activateMenuButton?.(button)) return;
    menuPointerID = e.pointerId;
    suppressMenuPointerClick = true;
    if (menuPointerResetTimer !== null) clearTimeout(menuPointerResetTimer);
    menuPointerResetTimer = setTimeout(clearMenuPointerSuppression, 1000);
    e.preventDefault();
    e.stopImmediatePropagation();
}, true);
window.addEventListener('pointerup', e => {
    if (e.pointerId !== menuPointerID) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    if (menuPointerResetTimer !== null) clearTimeout(menuPointerResetTimer);
    menuPointerResetTimer = setTimeout(clearMenuPointerSuppression, 0);
}, true);
window.addEventListener('pointercancel', e => {
    if (e.pointerId === menuPointerID) clearMenuPointerSuppression();
}, true);
window.addEventListener('click', e => {
    if (suppressMenuPointerClick) {
        clearMenuPointerSuppression();
        e.preventDefault();
        e.stopImmediatePropagation();
        return;
    }
    const target = e.target instanceof Element ? e.target : null;
    const button = e.button === 0 ? target?.closest('.video-player__menu-button') : null;
    if (!button || !activateMenuButton?.(button)) return;
    e.preventDefault();
    e.stopImmediatePropagation();
}, true);
const referenceCSS = `
#player .video-player__controls {
    position: absolute;
    inset: auto 0 0 0;
    z-index: 2;
    height: 72px;
    pointer-events: none;
}

#player .video-player__controls-bg {
    position: absolute;
    inset: 0;
    pointer-events: none;
    user-select: none;
    -webkit-user-drag: none;
    background: linear-gradient(
        180deg,
        rgba(0, 0, 0, 0) 0%,
        rgba(0, 0, 0, 0.12) 24%,
        rgba(0, 0, 0, 0.7) 100%
    );
}

#player .video-player__controls-inner {
    position: absolute;
    inset: 0 16px;
    z-index: 1;
    display: grid;
    grid-template-columns: 40px minmax(0, 1fr) auto;
    align-items: center;
    gap: 16px;
    pointer-events: none;
}

#player .video-player__button,
#player .video-player__toolbar-button,
#player .video-player__menu-button {
    appearance: none;
    border: 0;
    padding: 0;
    margin: 0;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.1);
    transition:
        background-color 0.18s ease,
        transform 0.18s ease,
        opacity 0.18s ease;
}

#player .video-player__button,
#player .video-player__toolbar-button {
    pointer-events: auto;
}

#player .video-player__button:hover,
#player .video-player__toolbar-button:hover {
    background: rgba(255, 255, 255, 0.25);
}

#player .video-player__toolbar-button.is-active {
    background: rgba(255, 255, 255, 0.3);
}

#player .video-player__button:active,
#player .video-player__toolbar-button:active {
    transform: scale(0.98);
}

#player .video-player__button:disabled,
#player .video-player__toolbar-button:disabled,
#player .video-player__menu-button:disabled {
    opacity: 0.45;
    cursor: default;
    transform: none;
}

#player .video-player__button {
    width: 40px;
    height: 40px;
    flex: 0 0 auto;
}

#player .video-player__toolbar {
    display: flex;
    align-items: center;
    gap: 8px;
    flex: 0 0 auto;
    pointer-events: auto;
}

#player .video-player__toolbar-button {
    width: 32px;
    height: 32px;
    flex: 0 0 auto;
}

#player .video-player__button-state[hidden],
#player .video-player__toolbar-state[hidden] {
    display: none !important;
}

#player .video-player__button-state,
#player .video-player__toolbar-state {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 16px;
    height: 16px;
    min-width: 0;
    min-height: 0;
    flex: 0 0 auto;
}

#player .video-player__glyph {
    display: block;
    width: 100%;
    height: 100%;
}

#player .video-player__button-state--play,
#player .video-player__button-state--pause {
    width: 16px;
    height: 16px;
}

#player .video-player__toolbar-state--volume {
    width: 14.333px;
    height: 12.057px;
}

#player .video-player__toolbar-state--cc {
    width: 18px;
    height: 14px;
    color: #fff;
    font: 700 10px/14px -apple-system, BlinkMacSystemFont, sans-serif;
    letter-spacing: -0.03em;
}

#player .video-player__toolbar-state--theater,
#player .video-player__toolbar-state--theater-exit {
    width: 13px;
    height: 13px;
}

#player .video-player__toolbar-state--more {
    width: 11.667px;
    height: 2.333px;
}

#player .video-player__timeline-group {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: center;
    gap: 16px;
    min-width: 0;
    width: 100%;
    flex: 1 1 auto;
    pointer-events: auto;
}

#player .video-player__timeline {
    position: relative;
    min-width: 0;
    width: auto;
    height: 24px;
    display: flex;
    align-items: center;
    cursor: pointer;
    touch-action: none;
    outline: none;
}

#player .video-player__timeline-track {
    position: relative;
    width: 100%;
    height: 6px;
    border-radius: 100px;
    background: rgba(255, 255, 255, 0.1);
    overflow: hidden;
    transition:
        height 0.18s ease,
        background-color 0.18s ease;
}

#player.is-video-hovering .video-player__timeline-track,
#player.is-video-scrubbing .video-player__timeline-track,
#player .video-player__timeline:focus-visible .video-player__timeline-track {
    height: 24px;
}

#player .video-player__timeline-fill {
    position: absolute;
    inset: 0 auto 0 0;
    width: var(--video-progress, 0%);
    border-radius: 100px 0 0 100px;
    background: rgba(255, 255, 255, 0.35);
}

#player .video-player__timeline-hover-line {
    position: absolute;
    top: 0;
    bottom: 0;
    left: var(--video-hover-ratio, 0%);
    width: 2px;
    transform: translateX(-1px);
    border-radius: 999px;
    background: #f47b20;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.12s ease;
}

#player .video-player__timeline-tooltip {
    position: absolute;
    left: var(--video-hover-ratio, 0%);
    bottom: calc(100% + 10px);
    transform: translateX(-50%) translateY(4px);
    padding: 6px 8px;
    border-radius: 999px;
    background: #f47b20;
    color: #fff;
    font-family:
        "Roboto Mono", "SFMono-Regular", ui-monospace, Menlo,
        Monaco, Consolas, "Liberation Mono", monospace;
    font-size: 12px;
    line-height: 1;
    white-space: nowrap;
    opacity: 0;
    pointer-events: none;
    transition:
        opacity 0.12s ease,
        transform 0.12s ease;
    box-shadow: 0 8px 20px rgba(244, 123, 32, 0.22);
}

#player.is-video-hovering .video-player__timeline-hover-line,
#player.is-video-scrubbing .video-player__timeline-hover-line,
#player.is-video-hovering .video-player__timeline-tooltip,
#player.is-video-scrubbing .video-player__timeline-tooltip,
#player .video-player__timeline:focus-visible .video-player__timeline-hover-line,
#player .video-player__timeline:focus-visible .video-player__timeline-tooltip {
    opacity: 1;
}

#player.is-video-hovering .video-player__timeline-tooltip,
#player.is-video-scrubbing .video-player__timeline-tooltip,
#player .video-player__timeline:focus-visible .video-player__timeline-tooltip {
    transform: translateX(-50%) translateY(0);
}

#player .video-player__time {
    flex: 0 0 auto;
    display: inline-flex;
    align-items: center;
    gap: 0;
    min-width: max-content;
    color: rgba(255, 255, 255, 0.8);
    font-family:
        "Roboto Mono", "SFMono-Regular", ui-monospace, Menlo,
        Monaco, Consolas, "Liberation Mono", monospace;
    font-size: 13px;
    line-height: 1;
    font-variant-numeric: tabular-nums slashed-zero;
    letter-spacing: -0.02em;
    white-space: nowrap;
    text-align: right;
}

#player .video-player__time-separator {
    color: rgba(255, 255, 255, 0.4);
    font-size: 14px;
    line-height: 1.25;
    padding: 0 1px;
}

#player .video-player__time-current {
    color: rgba(255, 255, 255, 0.6);
}

#player .video-player__time-duration {
    color: rgba(255, 255, 255, 0.8);
}

#player .video-player__menu {
    position: absolute;
    right: 16px;
    bottom: 80px;
    z-index: 3;
    width: 196px;
    box-sizing: border-box;
    padding: 12px 8px;
    border-radius: 12px;
    background:
        linear-gradient(
            0deg,
            rgba(255, 255, 255, 0.1) 0%,
            rgba(255, 255, 255, 0.1) 100%
        ),
        linear-gradient(
            180deg,
            rgba(37, 37, 39, 0.3) 0%,
            rgba(37, 37, 39, 0.6) 100%
        );
    backdrop-filter: blur(50px);
    -webkit-backdrop-filter: blur(50px);
    display: flex;
    flex-direction: column;
    gap: 0;
}

#player .video-player__menu[hidden] {
    display: none !important;
}

#player .video-player__menu-list {
    display: flex;
    flex-direction: column;
    gap: 0;
}

#player .video-player__menu-heading {
    padding: 0 6px;
    margin: 0 0 12px;
    color: rgba(255, 255, 255, 0.6);
    font-family:
        "Roboto Mono", "SFMono-Regular", ui-monospace, Menlo,
        Monaco, Consolas, "Liberation Mono", monospace;
    font-size: 13px;
    line-height: 1;
    letter-spacing: -0.02em;
}

#player .video-player__menu-button {
    width: 100%;
    min-height: 24px;
    justify-content: flex-start;
    border-radius: 6px;
    padding: 4px 8px;
    color: rgba(255, 255, 255, 0.8);
    background: transparent;
    font-size: 13px;
    line-height: 16px;
    letter-spacing: -0.02em;
    font-family:
        "Roboto Mono", "SFMono-Regular", ui-monospace, Menlo,
        Monaco, Consolas, "Liberation Mono", monospace;
    text-align: left;
    white-space: nowrap;
    transition:
        background-color 0.18s ease,
        color 0.18s ease;
}

#player .video-player__menu-button:hover {
    background: rgba(255, 255, 255, 0.08);
}

#player .video-player__menu-button.is-active {
    background: rgba(255, 255, 255, 0.13);
    color: rgba(255, 255, 255, 0.8);
}

#player .video-player__menu-divider {
    display: block;
    width: calc(100% + 16px);
    height: 1px;
    margin: 12px -8px;
    background: rgba(255, 255, 255, 0.08);
}

#player .video-player__sr {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
}

`;
const SVG_VIDEO_PLAY = `<svg class="video-player__glyph" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><g><path fill-rule="evenodd" clip-rule="evenodd" d="M6.67083 1.86812C6.6788 1.87344 6.6868 1.87877 6.69482 1.88411L13.7273 6.57244C13.9308 6.70807 14.1195 6.83382 14.2644 6.95068C14.4156 7.07264 14.5938 7.24175 14.6964 7.48916C14.8321 7.81616 14.8321 8.18367 14.6964 8.51068C14.5938 8.75808 14.4156 8.92719 14.2644 9.04915C14.1195 9.166 13.9308 9.29175 13.7273 9.42737L6.67085 14.1317C6.42213 14.2975 6.19848 14.4467 6.0087 14.5495C5.81879 14.6524 5.55812 14.77 5.25387 14.7519C4.8647 14.7286 4.5052 14.5362 4.26999 14.2253C4.08611 13.9822 4.03937 13.7001 4.01966 13.485C3.99996 13.2701 3.99998 13.0013 4 12.7023L4 3.32634C4 3.31669 4 3.30708 4 3.29751C3.99998 2.99857 3.99996 2.72978 4.01966 2.51483C4.03937 2.29972 4.08611 2.01759 4.26999 1.77452C4.5052 1.4636 4.8647 1.2712 5.25387 1.24796C5.55812 1.2298 5.81879 1.34741 6.0087 1.45033C6.19847 1.55317 6.42212 1.70229 6.67083 1.86812Z" fill="white"/></g></svg>`;
const SVG_VIDEO_PAUSE = `<svg class="video-player__glyph" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><g><rect x="3.33333" y="2" width="2.66667" height="12" rx="1" fill="white"/><rect x="10" y="2" width="2.66667" height="12" rx="1" fill="white"/></g></svg>`;
const SVG_VIDEO_VOLUME_ON = `<svg class="video-player__glyph" viewBox="0 0 14.3333 12.0572" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12.3319 1.36193C13.2768 2.67542 13.8333 4.28702 13.8333 6.0286C13.8333 7.77018 13.2768 9.38178 12.3319 10.6953M9.66354 3.36193C10.1908 4.11782 10.5 5.0371 10.5 6.0286C10.5 7.0201 10.1908 7.93938 9.66354 8.69527M5.58955 0.939056L3.47909 3.04951C3.36379 3.16481 3.30614 3.22247 3.23886 3.26369C3.17921 3.30025 3.11418 3.32718 3.04616 3.34351C2.96943 3.36193 2.8879 3.36193 2.72484 3.36193H1.56667C1.1933 3.36193 1.00662 3.36193 0.864008 3.4346C0.738567 3.49851 0.63658 3.6005 0.572664 3.72594C0.500002 3.86855 0.500002 4.05523 0.500002 4.4286V7.6286C0.500002 8.00197 0.500002 8.18865 0.572664 8.33126C0.63658 8.4567 0.738567 8.55869 0.864008 8.6226C1.00662 8.69527 1.1933 8.69527 1.56667 8.69527H2.72484C2.8879 8.69527 2.96943 8.69527 3.04616 8.71369C3.11418 8.73002 3.17921 8.75695 3.23886 8.79351C3.30614 8.83473 3.36379 8.89238 3.47909 9.00769L5.58954 11.1181C5.87513 11.4037 6.01792 11.5465 6.14052 11.5562C6.24689 11.5645 6.35084 11.5215 6.42014 11.4403C6.5 11.3468 6.5 11.1449 6.5 10.741V1.31618C6.5 0.912303 6.5 0.710365 6.42014 0.616855C6.35084 0.535719 6.24689 0.49266 6.14052 0.501032C6.01792 0.51068 5.87513 0.653472 5.58955 0.939056Z" stroke="white" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
const SVG_VIDEO_VOLUME_OFF = `<svg class="video-player__glyph" viewBox="0 0 14.3333 12.0572" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M13.8333 4.0286L9.83333 8.0286M9.83333 4.0286L13.8333 8.0286M5.58955 0.939056L3.47909 3.04951C3.36379 3.16481 3.30614 3.22247 3.23886 3.26369C3.17921 3.30025 3.11418 3.32718 3.04616 3.34351C2.96943 3.36193 2.8879 3.36193 2.72484 3.36193H1.56667C1.1933 3.36193 1.00662 3.36193 0.864008 3.4346C0.738567 3.49851 0.63658 3.6005 0.572664 3.72594C0.500002 3.86855 0.500002 4.05523 0.500002 4.4286V7.6286C0.500002 8.00197 0.500002 8.18865 0.572664 8.33126C0.63658 8.4567 0.738567 8.55869 0.864008 8.6226C1.00662 8.69527 1.1933 8.69527 1.56667 8.69527H2.72484C2.8879 8.69527 2.96943 8.69527 3.04616 8.71369C3.11418 8.73002 3.17921 8.75695 3.23886 8.79351C3.30614 8.83473 3.36379 8.89238 3.47909 9.00769L5.58954 11.1181C5.87513 11.4037 6.01792 11.5465 6.14052 11.5562C6.24689 11.5645 6.35084 11.5215 6.42014 11.4403C6.5 11.3468 6.5 11.1449 6.5 10.741V1.31618C6.5 0.912303 6.5 0.710365 6.42014 0.616855C6.35084 0.535719 6.24689 0.49266 6.14052 0.501032C6.01792 0.51068 5.87513 0.653472 5.58955 0.939056Z" stroke="white" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
const SVG_VIDEO_FULLSCREEN = `<svg class="video-player__glyph" viewBox="0 0 13 13" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M7.83333 5.16667L12.5 0.5M12.5 0.5H8.5M12.5 0.5V4.5M5.16667 7.83333L0.5 12.5M0.5 12.5H4.5M0.5 12.5L0.5 8.5" stroke="white" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
const SVG_VIDEO_FULLSCREEN_EXIT = `<svg class="video-player__glyph" viewBox="0 0 13 13" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M0.5 3.83333H0.633333C1.75344 3.83333 2.31349 3.83333 2.74131 3.61535C3.11764 3.4236 3.4236 3.11764 3.61535 2.74131C3.83333 2.31349 3.83333 1.75344 3.83333 0.633333V0.5M0.5 9.16667H0.633333C1.75344 9.16667 2.31349 9.16667 2.74131 9.38465C3.11764 9.5764 3.4236 9.88236 3.61535 10.2587C3.83333 10.6865 3.83333 11.2466 3.83333 12.3667V12.5M9.16667 0.5V0.633333C9.16667 1.75344 9.16667 2.31349 9.38465 2.74131C9.5764 3.11764 9.88236 3.4236 10.2587 3.61535C10.6865 3.83333 11.2466 3.83333 12.3667 3.83333H12.5M9.16667 12.5V12.3667C9.16667 11.2466 9.16667 10.6865 9.38465 10.2587C9.5764 9.88236 9.88236 9.5764 10.2587 9.38465C10.6865 9.16667 11.2466 9.16667 12.3667 9.16667H12.5" stroke="white" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
const SVG_VIDEO_MORE = `<svg class="video-player__glyph" viewBox="0 0 11.6667 2.33333" fill="none" xmlns="http://www.w3.org/2000/svg"><g><path d="M5.83333 1.83333C6.20152 1.83333 6.5 1.53486 6.5 1.16667C6.5 0.798477 6.20152 0.5 5.83333 0.5C5.46514 0.5 5.16667 0.798477 5.16667 1.16667C5.16667 1.53486 5.46514 1.83333 5.83333 1.83333Z" stroke="white" stroke-linecap="round" stroke-linejoin="round"/><path d="M10.5 1.83333C10.8682 1.83333 11.1667 1.53486 11.1667 1.16667C11.1667 0.798477 10.8682 0.5 10.5 0.5C10.1318 0.5 9.83333 0.798477 9.83333 1.16667C9.83333 1.53486 10.1318 1.83333 10.5 1.83333Z" stroke="white" stroke-linecap="round" stroke-linejoin="round"/><path d="M1.16667 1.83333C1.53486 1.83333 1.83333 1.53486 1.83333 1.16667C1.83333 0.798477 1.53486 0.5 1.16667 0.5C0.798477 0.5 0.5 0.798477 0.5 1.16667C0.5 1.53486 0.798477 1.83333 1.16667 1.83333Z" stroke="white" stroke-linecap="round" stroke-linejoin="round"/></g></svg>`;
const style = document.createElement('style');
style.textContent = referenceCSS + `
html,body { margin:0!important; padding:0!important; background:transparent!important; overflow:hidden!important; }
#player { z-index:0!important; inset:0!important; width:100%!important; height:100%!important; padding:0!important; background:#000!important; }
#player.yootube-video-present { background:transparent!important; }
html.yootube-player-fullscreen,
html.yootube-player-fullscreen body,
html.yootube-player-fullscreen #player { background:#000!important; }
html,body,#player,#player .vjs-tech { border:0!important; border-radius:0!important; box-shadow:none!important; }
.video-js { font-family:-apple-system,sans-serif; background:transparent!important; }
.video-js .vjs-tech { object-fit:contain; background:transparent!important; }
.video-js .vjs-control-bar,.video-js .vjs-big-play-button,.video-js .vjs-overlay-top,
.video-js .vjs-share-control,.watch-on-invidious { display:none!important; }
.video-js .vjs-text-track-display { bottom:76px!important; pointer-events:none; }
.video-player-shell { cursor:default!important; }
.video-player__controls,.video-player__menu { color:#fff; font-size:13px; line-height:normal; text-align:left; }
.video-player__menu { max-height:calc(100% - 96px); overflow-y:auto; overscroll-behavior:contain; }
.video-player__menu button { white-space:normal; }
.video-player__controls [hidden] { display:none!important; }
.video-player__controls button:focus-visible,.video-player__menu button:focus-visible { outline:2px solid #fff; outline-offset:2px; }
.video-player__timeline:focus-visible { outline:2px solid #fff; outline-offset:3px; border-radius:100px; }
.video-player__notice { position:absolute; top:16px; left:16px; right:16px; color:#fff; background:rgba(37,37,39,.93); padding:12px; border-radius:8px; z-index:4; font-size:13px; }
.video-player__notice[hidden] { display:none; }
@media(max-width:540px) {
  .video-player__controls-inner { inset:0 12px; gap:10px; }
  .video-player__timeline-group { gap:8px; }
  .video-player__time { font-size:11px; }
  .video-player__toolbar { gap:6px; }
}
@media(max-width:400px) {
  .video-player__timeline-group { grid-template-columns:1fr; gap:0; }
  .video-player__time { justify-content:center; }
}
@media(prefers-reduced-motion:reduce) {
  .video-player-shell * { transition:none!important; }
}
`;

function nativeVideoEngine(video) {
    if (!video) return null;
    const startText = new URLSearchParams(location.hash.slice(1)).get('t') || '';
    const parts = startText.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$/i);
    const startSeconds = parts
        ? Number(parts[1] || 0) * 3600 + Number(parts[2] || 0) * 60 + Number(parts[3] || 0)
        : Number(startText);
    if (Number.isFinite(startSeconds) && startSeconds > 0) {
        const seekToStart = () => {
            if (Number.isFinite(video.duration)) video.currentTime = Math.min(startSeconds, video.duration);
        };
        if (video.readyState >= 1) seekToStart();
        else video.addEventListener('loadedmetadata', seekToStart, {once:true});
    }
    const field = name => value => {
        if (value !== undefined) video[name] = value;
        return video[name];
    };
    return {
        el: () => document.getElementById('player'),
        ready: callback => callback(),
        duration: () => video.duration,
        currentTime: field('currentTime'),
        paused: () => video.paused,
        ended: () => video.ended,
        muted: field('muted'),
        volume: field('volume'),
        playbackRate: field('playbackRate'),
        textTracks: () => video.textTracks,
        audioTracks: () => video.audioTracks,
        qualityLevels: () => [],
        currentSources: () => [{
            label: (video.dataset.quality || tr('本地缓存'))
                .replace('（本地缓存）', window.yootubeLanguage === 'en' ? ' (local cache)' : '（本地缓存）'),
            selected:true
        }],
        tech: () => null,
        play: () => video.play(),
        pause: () => video.pause(),
        on: (names, callback) => (Array.isArray(names) ? names : [names])
            .forEach(name => video.addEventListener(name, callback)),
        trigger: () => {}
    };
}

function install() {
    let engine = null;
    try { engine = window.videojs?.getPlayer?.('player') || null; } catch {}
    if (!engine) engine = nativeVideoEngine(document.querySelector('#player video'));
    if (!engine) return; // Leave the upstream error page intact when no stream is available.
    engine.ready(() => {
        const shell = engine.el();
        if (shell.querySelector('.video-player__controls')) return;
        document.head.appendChild(style);
        shell.classList.add('video-player-shell');
        let videoFitTimer = null;
        let reportedAspectRatio = { value: 0 };
        const fitVideoToShell = () => {
            const video = shell.querySelector('.vjs-tech');
            const mediaAspect = Number(video?.videoWidth) / Number(video?.videoHeight);
            video?.style.setProperty('object-fit', 'contain', 'important');
            if (!Number.isFinite(mediaAspect) || mediaAspect <= 0) return false;
            if (Math.abs(reportedAspectRatio.value - mediaAspect) > 0.0005) {
                reportedAspectRatio.value = mediaAspect;
                window.webkit?.messageHandlers?.detailPlayback?.postMessage({
                    action: 'aspectRatio', value: mediaAspect
                });
            }
            return true;
        };
        const scheduleVideoFit = () => {
            if (videoFitTimer !== null) clearTimeout(videoFitTimer);
            let attempts = 0;
            const apply = () => {
                videoFitTimer = null;
                if (fitVideoToShell() || attempts >= 30) return;
                attempts += 1;
                videoFitTimer = setTimeout(apply, 100);
            };
            apply();
        };
        engine.on(['loadstart', 'loadedmetadata', 'loadeddata', 'canplay', 'playing'], scheduleVideoFit);
        window.addEventListener('resize', scheduleVideoFit);
        scheduleVideoFit();
        const state = (name, svg, cls = name, hidden = false) =>
            `<span data-icon="${name}" class="video-player__toolbar-state video-player__toolbar-state--${cls}" ${hidden ? 'hidden' : ''} aria-hidden="true">${svg}</span>`;
        const button = (action, label, content, cls = 'toolbar-button') =>
            `<button type="button" class="video-player__${cls}" data-action="${action}" aria-label="${label}" title="${label}">${content}</button>`;
        const controls = document.createElement('div');
        controls.className = 'video-player__controls';
        controls.innerHTML = `<div class="video-player__controls-bg" aria-hidden="true"></div>
          <div class="video-player__controls-inner">
            ${button('toggle', tr('播放'), state('play', SVG_VIDEO_PLAY) + state('pause', SVG_VIDEO_PAUSE, 'pause', true), 'button')}
            <div class="video-player__timeline-group">
              <div class="video-player__timeline" tabindex="0" role="slider" aria-label="${tr('视频进度')}" aria-valuemin="0" aria-valuemax="1000" aria-valuenow="0">
                <div class="video-player__timeline-track">
                  <div class="video-player__timeline-fill"></div>
                  <div class="video-player__timeline-hover-line" hidden></div>
                </div>
                <div class="video-player__timeline-tooltip" hidden>0:00</div>
              </div>
              <div class="video-player__time"><span data-current class="video-player__time-current">0:00</span><span class="video-player__time-separator">/</span><span data-duration class="video-player__time-duration">0:00</span></div>
            </div>
            <div class="video-player__toolbar">
              ${button('mute', tr('静音'), state('volume-on', SVG_VIDEO_VOLUME_ON, 'volume') + state('volume-off', SVG_VIDEO_VOLUME_OFF, 'volume', true))}
              ${button('captions', tr('开启字幕'), state('cc', 'CC', 'cc'))}
              ${button('theater', tr('影院模式'), state('theater', SVG_VIDEO_FULLSCREEN, 'theater') + state('theater-exit', SVG_VIDEO_FULLSCREEN_EXIT, 'theater-exit', true))}
              ${button('menu', tr('更多'), state('more', SVG_VIDEO_MORE, 'more'))}
            </div>
          </div>`;
        const menu = document.createElement('div');
        menu.className = 'video-player__menu';
        menu.id = 'yootube-player-menu';
        menu.hidden = true;
        menu.setAttribute('aria-label', tr('播放设置'));
        const notice = document.createElement('div');
        notice.className = 'video-player__notice';
        notice.setAttribute('role', 'status');
        notice.hidden = true;
        shell.append(controls, menu, notice);
        const menuActions = new WeakMap();
        activateMenuButton = button => {
            if (!menu.contains(button)) return false;
            const callback = menuActions.get(button);
            if (!callback) return false;
            callback();
            return true;
        };
        const find = selector => controls.querySelector(selector);
        const action = name => find(`[data-action="${name}"]`);
        const timeline = find('.video-player__timeline');
        const tooltip = find('.video-player__timeline-tooltip');
        const hoverLine = find('.video-player__timeline-hover-line');
        const qualityPreferenceKey = 'yootube.player.qualityHeight';
        let preferredQualityHeight = null;
        try {
            const savedHeight = Number(localStorage.getItem(qualityPreferenceKey));
            if (Number.isFinite(savedHeight) && savedHeight > 0) preferredQualityHeight = savedHeight;
        } catch {}
        let qualityApplyTimer = null, captionApplyTimer = null;
        let theaterMode = false, nativePlayerFullScreen = false;
        let pointer = null, lastCaptionKey = null, surfaceStartedPaused = null;
        let nativePictureInPictureState = 'inactive';
        let preferredCaptionKey;
        const media = () => shell.querySelector('video');
        const duration = () => Number.isFinite(engine.duration()) ? Math.max(0, engine.duration()) : 0;
        const clamp = (n, max = 1) => Math.min(max, Math.max(0, n));
        const listItems = list => {
            const items = [];
            for (let i = 0; list && i < list.length; i++) if (list[i]) items.push(list[i]);
            return items;
        };
        const captionTracks = () => listItems(engine.textTracks?.())
            .filter(track => track.kind === 'captions' || track.kind === 'subtitles');
        const audioTracks = () => listItems(engine.audioTracks?.());
        const qualityLevels = () => listItems(engine.qualityLevels?.())
            .filter(level => Number(level.height) > 0);
        function format(seconds) {
            const n = Math.max(0, Math.floor(seconds || 0));
            const s = String(n % 60).padStart(2, '0');
            const m = Math.floor(n / 60);
            return m >= 60 ? `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}:${s}` : `${m}:${s}`;
        }
        function label(name, text) {
            action(name).setAttribute('aria-label', text);
            action(name).title = text;
        }
        function icons(first, second, showSecond) {
            find(`[data-icon="${first}"]`).hidden = showSecond;
            find(`[data-icon="${second}"]`).hidden = !showSecond;
        }
        function sync() {
            // The reference has one custom control surface. WebKit may restore native
            // video controls when switching sources, so suppress that duplicate overlay.
            if (media()) media().controls = false;
            const total = duration(), current = engine.currentTime() || 0;
            const ratio = total ? clamp(current / total) : 0;
            shell.style.setProperty('--video-progress', `${ratio * 100}%`);
            find('[data-current]').textContent = format(current);
            find('[data-duration]').textContent = total ? format(total) : (engine.duration() === Infinity ? tr('直播') : '0:00');
            timeline.setAttribute('aria-valuenow', String(Math.round(ratio * 1000)));
            timeline.setAttribute('aria-valuetext', `${format(current)} / ${format(total)}`);
            timeline.setAttribute('aria-disabled', String(!total));
            const playing = !engine.paused() && !engine.ended();
            icons('play', 'pause', playing);
            label('toggle', tr(playing ? '暂停' : '播放'));
            const muted = engine.muted() || engine.volume() === 0;
            icons('volume-on', 'volume-off', muted);
            label('mute', tr(muted ? '取消静音' : '静音'));
            const captions = captionTracks();
            const captionsOn = captions.some(track => track.mode === 'showing');
            action('captions').disabled = captions.length === 0;
            action('captions').classList.toggle('is-active', captionsOn);
            action('captions').setAttribute('aria-pressed', String(captionsOn));
            label('captions', tr(captions.length ? (captionsOn ? '关闭字幕' : '开启字幕') : '当前视频没有字幕'));
            icons('theater', 'theater-exit', theaterMode);
            action('theater').classList.toggle('is-active', theaterMode);
            action('theater').setAttribute('aria-pressed', String(theaterMode));
            label('theater', tr(theaterMode ? '退出影院模式 · Esc' : '影院模式'));
            menu.querySelectorAll('[data-speed]').forEach(b => {
                const selected = Math.abs(Number(b.dataset.speed) - engine.playbackRate()) < 0.001;
                b.classList.toggle('is-active', selected);
                b.setAttribute('aria-pressed', String(selected));
            });
        }
        async function play() {
            notice.hidden = true;
            try { await engine.play(); }
            catch { notice.textContent = tr('暂时无法播放，请再次点击播放或重试加载。'); notice.hidden = false; }
            sync();
        }
        function toggle() { if (engine.paused() || engine.ended()) play(); else engine.pause(); }
        window.yootubeTogglePlayback = toggle;
        function playbackSnapshot() {
            const currentTime = Number(engine.currentTime());
            const volume = Number(engine.volume());
            const playbackRate = Number(engine.playbackRate());
            return {
                currentTime: Number.isFinite(currentTime) ? Math.max(0, currentTime) : 0,
                shouldPlay: !engine.paused() && !engine.ended(),
                muted: !!engine.muted(),
                volume: Number.isFinite(volume) ? clamp(volume) : 1,
                playbackRate: Number.isFinite(playbackRate) ? Math.min(4, Math.max(0.25, playbackRate)) : 1
            };
        }
        window.yootubeSetPictureInPictureState = state => {
            nativePictureInPictureState = state === 'active' ? 'active' :
                (state === 'preparing' ? 'preparing' : 'inactive');
            if (nativePictureInPictureState === 'active') notice.hidden = true;
        };
        window.yootubeFinishPictureInPicture = async payload => {
            nativePictureInPictureState = 'inactive';
            const state = payload?.state || {};
            const currentTime = Number(state.currentTime);
            const volume = Number(state.volume);
            const playbackRate = Number(state.playbackRate);
            if (Number.isFinite(currentTime) && currentTime >= 0) engine.currentTime(currentTime);
            if (Number.isFinite(volume)) engine.volume(clamp(volume));
            engine.muted(!!state.muted);
            if (Number.isFinite(playbackRate)) engine.playbackRate(Math.min(4, Math.max(0.25, playbackRate)));
            if (state.shouldPlay) await play();
            else { engine.pause(); sync(); }
            if (payload?.message) {
                notice.textContent = String(payload.message);
                notice.hidden = false;
            }
        };
        function closeMenu(restoreFocus = false) {
            menu.hidden = true;
            action('menu').setAttribute('aria-expanded', 'false');
            if (restoreFocus) action('menu').focus();
        }
        function setTheaterMode(value) {
            theaterMode = value;
            closeMenu();
            window.webkit?.messageHandlers?.detailPlayback?.postMessage(value ? 'theater' : 'standard');
            sync();
        }
        window.yootubeSetTheaterMode = value => { theaterMode = !!value; sync(); };
        window.yootubeSetPlayerFullScreen = value => {
            nativePlayerFullScreen = !!value;
            document.documentElement.classList.toggle('yootube-player-fullscreen', nativePlayerFullScreen);
        };
        window.yootubeToggleTheaterMode = () => setTheaterMode(!theaterMode);
        function menuButton(text, callback, selected = false) {
            const b = document.createElement('button');
            b.type = 'button'; b.className = 'video-player__menu-button'; b.textContent = text;
            b.classList.toggle('is-active', selected);
            b.setAttribute('aria-pressed', String(selected));
            menuActions.set(b, callback);
            menu.appendChild(b);
            return b;
        }
        function heading(text) {
            const h = document.createElement('div');
            h.className = 'video-player__menu-heading'; h.textContent = text;
            menu.appendChild(h);
        }
        function divider() {
            const d = document.createElement('div'); d.className = 'video-player__menu-divider';
            menu.appendChild(d);
        }
        const captionKey = track => [track.kind || '', track.language || '', track.label || ''].join('\u0000');
        function applyPreferredCaption() {
            if (preferredCaptionKey === undefined) return false;
            const tracks = captionTracks();
            const selected = preferredCaptionKey === null
                ? null
                : tracks.find(track => captionKey(track) === preferredCaptionKey);
            if (preferredCaptionKey !== null && !selected) return false;
            tracks.forEach(track => { track.mode = track === selected ? 'showing' : 'disabled'; });
            return true;
        }
        function schedulePreferredCaption() {
            if (captionApplyTimer !== null) clearTimeout(captionApplyTimer);
            captionApplyTimer = setTimeout(() => {
                captionApplyTimer = null;
                applyPreferredCaption();
                sync();
            }, 0);
        }
        function setCaption(track) {
            preferredCaptionKey = track ? captionKey(track) : null;
            if (track) lastCaptionKey = preferredCaptionKey;
            applyPreferredCaption();
            sync();
        }
        function toggleCaptions() {
            const tracks = captionTracks();
            if (!tracks.length) return;
            const showing = tracks.find(track => track.mode === 'showing');
            if (showing) {
                lastCaptionKey = captionKey(showing);
                setCaption(null);
            } else {
                setCaption(tracks.find(track => captionKey(track) === lastCaptionKey) || tracks[0]);
            }
        }
        function openSubmenu(title, choices) {
            menu.replaceChildren();
            menuButton(tr('‹ 返回'), () => { buildMenu(); menu.querySelector('button').focus(); });
            divider(); heading(title);
            choices.forEach(choice => {
                menuButton(choice.label, () => {
                    choice.select();
                    closeMenu(true);
                    sync();
                }, choice.selected);
            });
            menu.scrollTop = 0;
            menu.querySelector('button').focus();
        }
        function choiceMenu(title, makeChoices) {
            if (!makeChoices().length) return;
            menuButton(`${title} ›`, () => openSubmenu(title, makeChoices()));
        }
        function saveQualityPreference() {
            try {
                if (preferredQualityHeight === null) localStorage.removeItem(qualityPreferenceKey);
                else localStorage.setItem(qualityPreferenceKey, String(preferredQualityHeight));
            } catch {}
        }
        function switchToEnabledQuality() {
            try {
                engine.tech?.({ IWillNotUseThisInPlugins: true })
                    ?.vhs?.masterPlaylistController_?.fastQualityChange_?.();
            } catch {}
        }
        function applyPreferredQuality() {
            if (preferredQualityHeight === null) return false;
            const levels = qualityLevels();
            const targets = levels.filter(level => Number(level.height) === preferredQualityHeight);
            if (!targets.length) return false;
            const list = engine.qualityLevels?.();
            const selectedIndex = Number(list?.selectedIndex);
            const current = Number.isInteger(selectedIndex) && selectedIndex >= 0 ? list[selectedIndex] : null;
            targets.forEach(level => { level.enabled = true; });
            levels.filter(level => level !== current && !targets.includes(level))
                .forEach(level => { level.enabled = false; });
            if (current && !targets.includes(current)) current.enabled = false;
            if (!current || !targets.includes(current)) switchToEnabledQuality();
            return true;
        }
        function schedulePreferredQuality(delay = 0) {
            if (qualityApplyTimer !== null) clearTimeout(qualityApplyTimer);
            qualityApplyTimer = setTimeout(() => {
                qualityApplyTimer = null;
                applyPreferredQuality();
                sync();
            }, delay);
        }
        function qualityChoices() {
            const levels = qualityLevels();
            if (levels.length) {
                const heights = [...new Set(levels.map(level => Number(level.height)))].sort((a, b) => b - a);
                const selectHeight = height => {
                    preferredQualityHeight = height;
                    saveQualityPreference();
                    applyPreferredQuality();
                };
                return [{
                    label: tr('自动'), selected: preferredQualityHeight === null,
                    select: () => {
                        preferredQualityHeight = null;
                        saveQualityPreference();
                        qualityLevels().forEach(level => { level.enabled = true; });
                    }
                }, ...heights.map(height => ({
                    label: `${height}p`,
                    selected: preferredQualityHeight === height,
                    select: () => selectHeight(height)
                }))];
            }
            const sources = listItems(engine.currentSources?.()).filter(source => source.label);
            return sources.map(source => ({
                label: source.label === 'Auto' || source.label === 'dash' ? tr('自动') : source.label,
                selected: source.selected === true || source.selected === 'true',
                select: () => engine.trigger?.('qualityRequested', source)
            }));
        }
        function captionChoices() {
            const tracks = captionTracks();
            if (!tracks.length) return [];
            const showing = tracks.find(track => track.mode === 'showing');
            const selectedKey = preferredCaptionKey === undefined
                ? (showing ? captionKey(showing) : null)
                : preferredCaptionKey;
            return [{ label: tr('关闭字幕'), selected: selectedKey === null, select: () => setCaption(null) },
                ...tracks.map((track, index) => ({
                    label: track.label || track.language || `${tr('字幕')} ${index + 1}`,
                    selected: captionKey(track) === selectedKey,
                    select: () => setCaption(track)
                }))];
        }
        function audioChoices() {
            return audioTracks().map((track, index, tracks) => ({
                label: track.label || track.language || `${tr('音轨')} ${index + 1}`,
                selected: !!track.enabled,
                select: () => tracks.forEach(item => { item.enabled = item === track; })
            }));
        }
        function buildMenu() {
            menu.replaceChildren();
            heading(tr('播放速度'));
            [0.5, 1, 1.25, 1.5, 2].forEach(rate => {
                const b = menuButton(`${rate === 2 ? '2.0' : rate}x`, () => { engine.playbackRate(rate); sync(); });
                b.dataset.speed = String(rate);
            });
            divider();
            const v = media();
            const nativePipBridge = window.webkit?.messageHandlers?.detailPlayback;
            const standardPip = document.pictureInPictureEnabled && v?.requestPictureInPicture && !v.disablePictureInPicture;
            const webkitPip = v?.webkitSupportsPresentationMode?.('picture-in-picture');
            const isPip = nativePictureInPictureState === 'active' ||
                document.pictureInPictureElement === v || v?.webkitPresentationMode === 'picture-in-picture';
            const pip = menuButton(tr(isPip ? '退出画中画' : '画中画'), async () => {
                let handedOffState = null;
                try {
                    if (nativePipBridge) {
                        if (nativePictureInPictureState === 'active') {
                            nativePipBridge.postMessage({action:'stopPictureInPicture'});
                        } else {
                            const state = playbackSnapshot();
                            handedOffState = state;
                            nativePictureInPictureState = 'preparing';
                            engine.pause();
                            sync();
                            notice.textContent = tr('正在准备画中画…');
                            notice.hidden = false;
                            nativePipBridge.postMessage({action:'pictureInPicture', state});
                        }
                    } else if (standardPip) {
                        if (document.pictureInPictureElement === v) await document.exitPictureInPicture();
                        else await v.requestPictureInPicture();
                    } else if (webkitPip) {
                        v.webkitSetPresentationMode(v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture');
                    }
                    closeMenu(true);
                } catch {
                    if (handedOffState) {
                        window.yootubeFinishPictureInPicture({
                            state: handedOffState,
                            message: tr('当前视频暂时无法进入画中画。')
                        });
                    } else {
                        notice.textContent = tr('当前视频暂时无法进入画中画。');
                        notice.hidden = false;
                    }
                }
            });
            pip.disabled = nativePictureInPictureState === 'preparing' ||
                !(nativePipBridge || standardPip || webkitPip);
            if (pip.disabled) pip.title = tr('当前播放环境不支持画中画');
            divider();
            choiceMenu(tr('清晰度'), qualityChoices);
            choiceMenu(tr('字幕'), captionChoices);
            choiceMenu(tr('音轨'), audioChoices);
            sync();
        }
        window.yootubeSetLanguage = language => {
            window.yootubeLanguage = language === 'en' ? 'en' : 'zh-Hans';
            timeline.setAttribute('aria-label', tr('视频进度'));
            menu.setAttribute('aria-label', tr('播放设置'));
            label('menu', tr('更多'));
            if (!menu.hidden) buildMenu();
            sync();
        };
        action('menu').setAttribute('aria-controls', menu.id);
        action('menu').setAttribute('aria-expanded', 'false');
        action('toggle').addEventListener('click', toggle);
        function toggleMute() {
            if (engine.volume() === 0) { engine.volume(0.5); engine.muted(false); }
            else engine.muted(!engine.muted());
            sync();
        }
        action('mute').addEventListener('click', toggleMute);
        action('captions').addEventListener('click', toggleCaptions);
        window.yootubeToggleMute = toggleMute;
        window.yootubeToggleCaptions = toggleCaptions;
        action('theater').addEventListener('click', () => setTheaterMode(!theaterMode));
        action('menu').addEventListener('click', () => {
            if (!menu.hidden) return closeMenu();
            buildMenu(); menu.hidden = false;
            action('menu').setAttribute('aria-expanded', 'true');
        });
        document.addEventListener('pointerdown', e => {
            if (!menu.contains(e.target) && !action('menu').contains(e.target)) closeMenu();
        }, true);
        document.addEventListener('focusin', e => {
            if (!menu.contains(e.target) && !action('menu').contains(e.target)) closeMenu();
        });
        const isMediaSurface = target => target &&
            !target.closest('.video-player__controls,.video-player__menu,button,a,input,select,textarea');
        const rememberSurfaceState = e => {
            const target = e.target instanceof Element ? e.target : null;
            surfaceStartedPaused = e.button === 0 && isMediaSurface(target)
                ? engine.paused() || engine.ended()
                : null;
        };
        shell.addEventListener('pointerdown', rememberSurfaceState, true);
        shell.addEventListener('mousedown', rememberSurfaceState, true);
        shell.addEventListener('pointercancel', () => { surfaceStartedPaused = null; }, true);
        // WebKit can apply the video element's own play/pause action before `click`.
        // Use the state from pointer-down so that our handler confirms the intended
        // result instead of toggling the already-toggled player a second time.
        shell.addEventListener('click', e => {
            const target = e.target instanceof Element ? e.target : null;
            if (!isMediaSurface(target)) return;
            const shouldPlay = surfaceStartedPaused ?? (engine.paused() || engine.ended());
            surfaceStartedPaused = null;
            e.preventDefault(); e.stopImmediatePropagation();
            if (shouldPlay) {
                if (engine.paused() || engine.ended()) play(); else sync();
            } else {
                if (!engine.paused() && !engine.ended()) engine.pause();
                sync();
            }
            shell.focus();
        }, true);
        shell.addEventListener('dblclick', e => {
            const target = e.target instanceof Element ? e.target : null;
            if (isMediaSurface(target)) {
                e.preventDefault(); e.stopImmediatePropagation();
            }
        }, true);
        function ratioAt(x) {
            const rect = timeline.getBoundingClientRect();
            return rect.width ? clamp((x - rect.left) / rect.width) : 0;
        }
        function hover(ratio) {
            if (!duration()) return;
            shell.classList.add('is-video-hovering');
            tooltip.hidden = hoverLine.hidden = false;
            shell.style.setProperty('--video-hover-ratio', `${ratio * 100}%`);
            tooltip.textContent = format(duration() * ratio);
        }
        function clearHover() {
            shell.classList.remove('is-video-hovering');
            tooltip.hidden = hoverLine.hidden = true;
        }
        function seek(ratio) { if (duration()) { engine.currentTime(duration() * clamp(ratio)); sync(); hover(ratio); } }
        timeline.addEventListener('pointerenter', e => hover(ratioAt(e.clientX)));
        timeline.addEventListener('pointermove', e => {
            if (pointer !== null && e.pointerId !== pointer) return;
            const ratio = ratioAt(e.clientX); hover(ratio);
            if (pointer !== null) seek(ratio);
        });
        timeline.addEventListener('pointerleave', () => { if (pointer === null) clearHover(); });
        timeline.addEventListener('pointerdown', e => {
            if (!duration() || e.button !== 0 || pointer !== null) return;
            e.preventDefault(); timeline.focus(); pointer = e.pointerId;
            timeline.setPointerCapture(pointer);
            shell.classList.add('is-video-scrubbing');
            seek(ratioAt(e.clientX)); play(); // The reference resumes playback when seeking by pointer.
        });
        function finishScrubbing() {
            const oldPointer = pointer; pointer = null;
            shell.classList.remove('is-video-scrubbing'); clearHover();
            if (oldPointer !== null && timeline.hasPointerCapture(oldPointer)) timeline.releasePointerCapture(oldPointer);
        }
        timeline.addEventListener('pointerup', e => {
            if (e.pointerId !== pointer) return;
            seek(ratioAt(e.clientX)); finishScrubbing();
            const r = timeline.getBoundingClientRect();
            if (e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom) hover(ratioAt(e.clientX));
        });
        timeline.addEventListener('pointercancel', finishScrubbing);
        timeline.addEventListener('lostpointercapture', () => { if (pointer !== null) finishScrubbing(); });
        timeline.addEventListener('focus', () => hover(duration() ? engine.currentTime() / duration() : 0));
        timeline.addEventListener('blur', () => { if (pointer === null) clearHover(); });
        // Handle our controls before the upstream global shortcuts, preventing double seeks/toggles.
        window.addEventListener('keydown', e => {
            const target = e.target instanceof Element ? e.target : document.body;
            if (e.metaKey || e.ctrlKey || e.altKey || target.matches('input,textarea,select,[contenteditable=true]')) return;
            let handled = true;
            if (e.key === 'Escape') {
                if (!menu.hidden) closeMenu(true);
                else if (nativePlayerFullScreen) {
                    const bridge = window.webkit?.messageHandlers?.detailPlayback;
                    if (bridge) bridge.postMessage('exitPlayerFullScreen');
                    else handled = false;
                }
                else if (theaterMode) setTheaterMode(false);
                else handled = false;
            }
            else if (e.key === 'f') {
                const bridge = window.webkit?.messageHandlers?.detailPlayback;
                if (bridge) bridge.postMessage('displayCycle');
                else setTheaterMode(!theaterMode);
            }
            else if (e.key === 't') setTheaterMode(!theaterMode);
            else if (e.key === 'c') toggleCaptions();
            else if (e.key === 'm') action('mute').click();
            else if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key) && e.target === timeline) {
                if (duration()) {
                    const next = e.key === 'Home' ? 0 : e.key === 'End' ? duration() : engine.currentTime() + (e.key === 'ArrowLeft' ? -5 : 5);
                    seek(clamp(next, duration()) / duration());
                }
            } else if ((e.key === ' ' || e.key === 'Enter') && target.closest('button')) {
                // Native button activation remains responsible for Space/Return.
                e.stopImmediatePropagation(); return;
            } else if (e.key === ' ' || e.key === 'k') toggle();
            else handled = false;
            if (handled) { e.preventDefault(); e.stopImmediatePropagation(); }
        }, true);
        engine.on(['loadedmetadata', 'durationchange', 'timeupdate', 'play', 'pause', 'ended', 'volumechange', 'ratechange', 'loadstart'], sync);
        engine.on(['loadedmetadata', 'loadstart'], schedulePreferredQuality);
        const textTrackList = engine.textTracks?.();
        const qualityList = engine.qualityLevels?.();
        [textTrackList, engine.audioTracks?.(), qualityList].forEach(list => {
            if (typeof list?.on === 'function') list.on('change', sync);
            else list?.addEventListener?.('change', sync);
        });
        if (typeof textTrackList?.on === 'function') {
            textTrackList.on('change', schedulePreferredCaption);
            textTrackList.on('addtrack', schedulePreferredCaption);
        } else {
            textTrackList?.addEventListener?.('change', schedulePreferredCaption);
            textTrackList?.addEventListener?.('addtrack', schedulePreferredCaption);
        }
        if (typeof qualityList?.on === 'function') qualityList.on('addqualitylevel', schedulePreferredQuality);
        else qualityList?.addEventListener?.('addqualitylevel', schedulePreferredQuality);
        const handlePlaying = () => {
            shell.classList.add('yootube-video-present');
            notice.hidden = true;
            window.webkit?.messageHandlers.detailPlayback.postMessage('playing');
        };
        const handleEnded = () => {
            window.webkit?.messageHandlers.detailPlayback.postMessage('ended');
        };
        engine.on('playing', handlePlaying);
        engine.on('ended', handleEnded);
        window.addEventListener('pagehide', () => {
            finishScrubbing();
            if (videoFitTimer !== null) clearTimeout(videoFitTimer);
            if (qualityApplyTimer !== null) clearTimeout(qualityApplyTimer);
            if (captionApplyTimer !== null) clearTimeout(captionApplyTimer);
        });
        window.addEventListener('blur', () => { closeMenu(); finishScrubbing(); });
        applyPreferredQuality();
        if (!engine.paused() && !engine.ended()) handlePlaying();
        sync();
    });
}
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install, { once:true });
else install();
})();
