# CapCut Feature Reference — What each feature does & how it's implemented

A comprehensive catalog of CapCut's video-editing features, grouped by category.
For each feature: **What it does**, **How CapCut implements it** (the underlying
technique), and **Impl for a renderer** (how you'd build the same thing, mapped to
FFmpeg filters or an ML model, relevant to this project's FFmpeg pipeline).

> Legend for the "Impl" notes:
> - **FFmpeg** = achievable with a filter graph today.
> - **Shader** = per-pixel GPU work (GLSL/Metal); CapCut does this in real time.
> - **ML** = needs a neural network model (segmentation, ASR, SR, etc.).
> - **Timeline** = editor/data-model logic, not a render filter.

---

## 1. Core timeline & clip editing

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Multi-track timeline** | Stack video, overlay, audio, text, sticker, effect, filter tracks; composited top-down. | Layered scene graph; each track = ordered list of clips with in/out + transform; renderer composites bottom→top per frame. | Timeline data model + FFmpeg `overlay`/`concat`; render each layer then composite. |
| **Split / cut (razor)** | Cut a clip at the playhead into two independent clips. | Timeline op: clone clip, set clip A out=t, clip B in=t. No re-encode. | Timeline: store source in/out offsets; only cut on export via `-ss`/`-to` + `trim`. |
| **Trim (drag edges)** | Shorten/extend a clip from either end. | Adjusts clip in/out pointers into the source; non-destructive. | Timeline metadata (in/out seconds). |
| **Ripple delete** | Delete a segment and close the gap. | Remove clip, shift downstream clips left by its duration. | Timeline op. |
| **Split-and-detach audio** | Separate a clip's audio to its own track. | Demux audio stream into a linked audio clip. | FFmpeg `-map` to split A/V; link in model. |
| **Copy / paste / duplicate** | Reuse clips and their attributes. | Deep-copy clip node incl. keyframes/effects. | Timeline op. |
| **Replace clip** | Swap source media, keep edits (duration, effects). | Rebind clip's media reference; clamp in/out to new length. | Timeline op. |
| **Freeze frame** | Insert a still of the current frame. | Sample frame at t, insert as image clip of chosen duration. | FFmpeg extract frame (`select`) → loop image (`tpad`/`loop`). |
| **Reverse** | Play a clip backward. | Decode to frames, emit in reverse; audio reversed too. | FFmpeg `reverse` + `areverse` (buffers whole clip — memory heavy). |
| **Snap / magnetic timeline** | Clips/keyframes snap to edges, playhead, beats. | Snapping thresholds in UI coordinate space. | Editor UI logic. |
| **Undo/redo** | Revert edits. | Command stack / immutable state diffs. | Editor state mgmt. |
| **Zoom timeline / preview scrubbing** | Frame-accurate navigation. | Proxy/thumbnail cache; seek to nearest keyframe + decode. | Generate thumbnail sprite via FFmpeg `fps`+`tile`. |

---

## 2. Speed & time remapping

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Constant speed** | Uniform slow/fast (0.1×–100×). | Remap output time → source time linearly; drop/duplicate frames. | FFmpeg `setpts=PTS/ N` (video) + `atempo` (audio). |
| **Speed curve (ramping)** | Non-linear speed with control points (presets: Montage, Hero, Bullet, Flash in/out, Jump cut). | Time-warp function T_src = f(T_out) defined by a Bézier curve of speed keyframes; integrate to map frames. | Precompute per-frame PTS mapping table; feed as `setpts` expression or VFR remap. |
| **Optical-flow slow-mo ("smooth slow motion")** | Interpolates *new* in-between frames for fluid slow motion instead of duplicating. | ML/optical-flow frame interpolation (RIFE/DAIN-style) synthesizes intermediate frames. | FFmpeg `minterpolate` (motion-compensated) — this project already exposes an interpolation toggle; or an ML interpolator for quality. |
| **Freeze + speed combos** | Hold then resume. | Composite of freeze-frame + speed segments. | Timeline segmentation. |

---

## 3. Transitions (between clips)

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Dissolve / fade / fade-to-black-white** | Cross-blend two clips. | Overlap the two clips by the transition duration; shader mixes texture A→B by alpha(t). | FFmpeg `xfade` (has dissolve, fade, and dozens of presets). |
| **Motion transitions (whip/pan/zoom/spin)** | Camera-style movement between clips. | Shader warps UVs (translate/scale/rotate) of A and B over the overlap. | `xfade` motion presets or custom GL; approximate with `zoompan`+`overlay` blend. |
| **Glitch / RGB split / light leaks** | Stylized cuts. | Fragment shaders (channel offset, noise, overlay textures). | Shader; FFmpeg `xfade` custom expr for simple ones. |
| **Transition duration/alignment** | How long, centered on the cut. | Overlap window centered/leading/trailing on the edit point. | `xfade offset=` + `duration=`. |

---

## 4. Overlays, Picture-in-Picture & compositing

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Overlay / PiP** | Layer a second video above the main. | Extra video track composited with its own transform. | FFmpeg `overlay` with scaled/positioned input. |
| **Transform (position/scale/rotation/opacity)** | Move, resize, rotate, fade any clip. | Per-clip 2D affine matrix + alpha applied at composite. | `scale`,`rotate`,`pad`,`overlay`,`format=rgba,colorchannelmixer aa=`. |
| **Blend modes** | Screen, multiply, overlay, add, darken, lighten, etc. | Shader blend equations between layer and backdrop. | FFmpeg `blend=all_mode=screen/multiply/overlay/...`. |
| **Canvas / background** | Set aspect ratio; fill empties with color/blur/image/gradient. | Background layer under content; blurred copy of video is common. | `scale`+`boxblur` bg + `overlay` fg; or `pad`/`drawbox`. |
| **Aspect-ratio presets** | 9:16, 16:9, 1:1, 4:5, 4:3, etc. | Canvas size + fit/fill mode. | `scale`+`crop`/`pad` to target. |

---

## 5. Masking

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Shape masks** | Linear, mirror, circle, rectangle, heart, star reveal a region. | Alpha mask (SDF or texture) multiplied into the layer's alpha in shader; adjustable center/size/rotation. | FFmpeg `geq`/`alphamerge` with a generated mask, or `maskedmerge`. |
| **Feather** | Soft mask edges. | Blur the mask alpha (gaussian falloff). | Blur the mask (`gblur`) before merge. |
| **Invert mask** | Swap kept/hidden region. | 1 − alpha. | `negate` the mask alpha. |
| **Animated masks** | Mask moves/scales via keyframes. | Mask transform is keyframed like any transform. | Per-frame mask params. |

---

## 6. Chroma key (green screen)

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Chroma key** | Remove a color (green/blue/any). | Pick key color; alpha = f(color distance) in shader; spill suppression + edge feather. | FFmpeg `chromakey`/`colorkey` + `despill`; feather via alpha blur. |
| **Intensity / shadow / feather** | Tune tolerance and edges. | Threshold + softness params on the distance function. | `similarity`/`blend` params of `chromakey`. |

---

## 7. Keyframing & animation

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Property keyframes** | Animate position, scale, rotation, opacity, volume, filter/effect intensity, mask, etc. | Each animatable param stores a list of (time,value); renderer interpolates (linear/Bézier ease) per frame and applies. | Per-frame param evaluation feeding `overlay`/`scale`/`rotate` expressions or `sendcmd`/`zoompan`. |
| **Ease in/out (graph)** | Non-linear interpolation. | Bézier easing between keyframes. | Precompute eased values per frame. |
| **Clip animations (In / Out / Combo)** | One-tap entrance/exit motion presets (fade, slide, zoom, bounce, etc.). | Predefined keyframe templates on transform/opacity for first/last N frames. | Prebuilt keyframe recipes. |
| **Ken Burns / zoom-pan** | Slow push/pan on stills or video. | Keyframed scale+position. | FFmpeg `zoompan`. |

---

## 8. Color & adjustment

CapCut's color tools split into four groups: **Adjust** (individual sliders),
**HSL** (per-color-band), **Curves** (tone splines), **Color wheels** (lift/gamma/
gain, desktop/advanced), plus the **Filters** tab (LUT looks). Every option below is
enumerated with its effect direction and how to implement it.

### 8a. Adjust sliders (each is a keyframeable −100…+100 slider unless noted)

| Slider | What it changes | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Brightness** | Overall luminance up/down. | Adds a constant to luma. | `eq=brightness=` (−1…1) or `curves` linear lift. |
| **Contrast** | Separation between darks and lights around mid-grey. | Scales luma about 0.5. | `eq=contrast=` (0…2). |
| **Saturation** | Intensity of all colors (0 = grey). | Scales chroma in HSV/YUV. | `eq=saturation=` or `hue=s=`. |
| **Vibrance / Light Sensation** (some builds) | Boosts muted colors more than already-saturated ones; protects skin. | Non-linear saturation weighted by current sat. | `vibrance` filter. |
| **Sharpen** | Edge acuity / crispness. | Unsharp mask (high-pass add-back). | `unsharp=luma_amount=`. |
| **Clarity / Structure** (some builds) | Local mid-tone contrast (punch). | Large-radius local contrast. | `unsharp` big radius / `smartblur` inverse. |
| **Highlights** | Brightness of the *bright* regions only. | Tone-curve lift/drop of upper range. | `curves` upper control point / `colorlevels`. |
| **Shadows** | Brightness of the *dark* regions only. | Tone-curve lift/drop of lower range. | `curves` lower control point / `colorlevels`. |
| **Whites** (some builds) | Clip point of the brightest pixels. | Sets white input level. | `colorlevels omax`/`curves` top anchor. |
| **Blacks** (some builds) | Crush point of the darkest pixels. | Sets black input level. | `colorlevels imin`/`curves` bottom anchor. |
| **Exposure** (some builds) | Photographic stops of light. | Multiplicative gain on linear light. | `eq=gamma`/`exposure` (via `zscale`+gain). |
| **Temperature** | Warm (amber) ↔ cool (blue). | Shifts blue/red balance. | `colortemperature=temperature=` or `colorbalance` (rs/bs). |
| **Tint / Hue-tint** | Green ↔ magenta cast. | Shifts green/magenta balance. | `colorbalance` (gs/… ) / `hue`. |
| **Hue (global)** | Rotates *all* colors around the wheel. | Rotates hue angle. | `hue=h=degrees`. |
| **Fade** | Lifts blacks for a flat/matte film look. | Raises black point (milky shadows). | `curves` raise the (0,0) anchor toward (0,0.1). |
| **Vignette** | Darkens/lightens frame corners. | Radial luminance falloff mask. | `vignette` (angle/x0/y0) or radial `geq` mask. |
| **Grain / Noise** | Adds film grain texture. | Random noise added per pixel. | `noise=alls=…:allf=t`. |
| **Highlight tint / Shadow tint** (split-tone, some builds) | Color-tints highlights vs shadows separately. | Two-zone color balance. | `colorbalance` highlights(rh/gh/bh) + shadows(rs/gs/bs). |

### 8b. HSL — per-color-band control

CapCut exposes **8 color bands**: **Red, Orange, Yellow, Green, Cyan (Aqua), Blue,
Purple, Magenta (Pink)**. Each band has three sub-sliders:

| Sub-slider | What it does | Impl for a renderer |
|---|---|---|
| **Hue** | Nudges that band's hue toward its neighbors. | Hue-range mask in HSV → rotate hue only inside the band (`geq`/`hue` gated by hue window), or `selectivecolor`. |
| **Saturation** | Saturates/desaturates only that band (e.g., kill only greens). | Same hue mask → scale S inside it. |
| **Luminance** | Brightens/darkens only that band. | Same hue mask → scale V/luma inside it. |

> Implementation pattern: build a soft mask `m(hue)` that is 1 inside the band's hue
> window and feathers to 0 at the edges; apply `newHSV = HSV + m·(deltaH, deltaS,
> deltaL)`. In FFmpeg approximate with `selectivecolor` or a `geq` per channel keyed
> on hue.

### 8c. Curves

| Channel | What it does | Impl for a renderer |
|---|---|---|
| **Luminance (RGB composite)** | Master tone curve — contrast, fade, S-curve. | `curves=master='0/0 0.25/0.2 0.75/0.85 1/1'`. |
| **Red** | Red channel tone → warm/cool tuning. | `curves=red='…'`. |
| **Green** | Green channel tone → magenta/green tuning. | `curves=green='…'`. |
| **Blue** | Blue channel tone → classic teal-shadows / warm-highlights. | `curves=blue='…'`. |

Each channel is an editable spline with add/drag/delete control points → CapCut fits
a smooth curve = a 1D LUT per channel (exactly what FFmpeg `curves` does).

### 8d. Color wheels (lift / gamma / gain — desktop/advanced grading)

| Wheel | Tonal zone it colors | Impl for a renderer |
|---|---|---|
| **Lift** | Shadows — tint + raise/lower black level. | `colorbalance` shadows (rs/gs/bs) + black-point. |
| **Gamma** | Midtones — tint + brightness of mids. | `colorbalance` midtones (rm/gm/bm) + `eq=gamma`. |
| **Gain** | Highlights — tint + white level. | `colorbalance` highlights (rh/gh/bh) + white-point. |
| **Offset** | Whole image — global color/brightness shift. | Global add via `colorlevels`/`curves`. |

Each wheel = a 2D color pick (angle=hue, distance=strength) + a master ring
(brightness) for that zone. Best baked to a generated **3D LUT** and applied with
`lut3d`.

### 8e. Filters (the "Filters" tab = one-tap LUT looks)

All filters are a **3D LUT (`.cube`)** sampled per pixel → implement with
`lut3d=file.cube`, and the **Intensity 0–100%** slider = blend filtered↔original
(`blend`/opacity lerp). The named categories (representative presets in each; exact
names/counts vary by version, region, and Pro tier):

| Category | Representative looks | Character |
|---|---|---|
| **Trending / Hot** | rotating popular LUTs | mixed, current-trend looks. |
| **Life / Daily** | Natural, Clean, Bright, Soft | subtle everyday correction. |
| **Portrait / People** | Natural, Clear, Fair, Cream, Rosy, Milk, Smooth | flattering skin tones. |
| **Food** | Delicious, Fresh, Sweet, Yummy | warm, saturated, appetizing. |
| **Scenery / Landscape** | Vivid, Clear Sky, Green, Bright | boosted greens/blues + clarity. |
| **Retro / Film** | Vintage, Retro, 1990s, Super-8, Kodak-like, Faded | grain + faded blacks + warm cast. |
| **Mono / B&W** | Mono, B&W, Noir, Ink, Contrast B&W | desaturate + tuned luma curve. |
| **Movie / Cinematic** | Cinematic, Teal-Orange, Blockbuster, Epic | split-tone teal shadows / warm skin. |
| **Vibe / Style** | Cyberpunk, Neon, Vaporwave, Moody | stylized, strong color grade. |
| **Cool tone / Warm tone** | Cool, Warm variants | pure temperature-leaning looks. |
| **Vlog** | Vlog Natural, Vlog Bright | flat, gradable, low-contrast. |
| **Beauty** | Soft, Glow, Fair | brighten + gentle skin smoothing pairing. |

### 8f. Auto-adjust

One-tap correction: histogram + white-balance analysis sets the §8a sliders. →
Analyze with `signalstats`/histogram, then apply `eq`/`curves`/`colorbalance`.

---

## 9. Text, titles & captions

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Add text** | Editable text with font, size, color, alignment. | Text rasterized to a texture layer with transform. | FFmpeg `drawtext` (or render PNG via a text engine → overlay for rich styling). |
| **Styles** | Stroke/outline, shadow, glow, background box, bubble, opacity, letter/line spacing. | Per-glyph rendering params in the text rasterizer. | `drawtext` (bordercolor/shadow/box) or pre-rendered RGBA. |
| **Text templates** | Designer presets combining style+animation. | Bundled style+keyframe packages. | Prebuilt style+animation recipes. |
| **Text animations (In/Out/Loop)** | Typewriter, fade, pop, wave, etc. | Keyframed transform/opacity, often per-character. | Per-char keyframes → overlay sequence. |
| **Auto captions (speech-to-text)** | Auto-transcribe spoken audio into timed subtitles. | On-device/cloud **ASR** model → word timestamps → styled caption clips. | ML ASR (Whisper-class) → `.srt` → `subtitles`/`ass` burn-in. |
| **Caption translation** | Translate captions to other languages. | ASR → MT (machine translation) model. | ML MT on transcript. |
| **Text-to-speech (TTS)** | Turn text into spoken voiceover with selectable voices. | Neural TTS synthesizes audio; placed on an audio track. | ML TTS model → audio clip. |
| **Text-to-video / script mode** | Generate a video from a script. | NLP splits script → matches stock/media + TTS + captions. | Orchestration + TTS + asset matching. |
| **Text tracking** | Pin text to a moving object. | Object/point tracker feeds text position keyframes. | ML/optical-flow tracker → position keyframes. |

---

## 10. Audio

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Volume + volume keyframes** | Level control and fades over time. | Per-sample gain envelope from keyframes. | `volume` (expr) / `afade`. |
| **Fade in/out** | Ramp audio at edges. | Linear/curve gain ramp. | `afade=in/out`. |
| **Extract audio** | Pull audio off a video. | Demux/copy audio stream. | `-map a` / `-vn`. |
| **Beat detection** | Auto-mark music beats to cut on. | **Onset detection** — spectral-flux/energy peaks over time → beat markers. | Offline onset detection (aubio/librosa-style); place markers. |
| **Audio ducking** | Auto-lower music under voiceover. | **Envelope follower / sidechain** — detect voice level, attenuate music inversely. | FFmpeg `sidechaincompress`. |
| **Noise reduction** | Remove hiss/hum/background. | Spectral gating / ML denoiser. | `afftdn`/`arnndn` (RNN model). |
| **Voice changer / effects** | Robot, chipmunk, echo, reverb, low/hi. | Pitch shift + formant + IR reverb DSP. | `asetrate`+`atempo` (pitch), `aecho`, `afreqshift`, `aphaser`. |
| **Sound effects & music library** | Royalty-safe SFX/music, categorized. | Licensed catalog streamed/downloaded; auto-attribution. | Asset library + licensing (business, not render). |
| **Voice isolation / vocal separation** | Split vocals from music. | **Source separation** ML model (stem splitting). | ML stem separation (Demucs-class). |
| **Auto-sync to beat** | Align cuts to detected beats. | Beat markers snap clip boundaries. | Beat markers + timeline snap. |

---

## 11. Effects (video/visual)

The **Effects** tab has three sub-tabs: **Video Effects** (whole-frame), **Body
Effects** (locked to a detected person), and **Photo/Image Effects** (for stills).
An effect is placed on its own effect-track clip over a time range and is composited
on top of the layers beneath it.

### 11a. Every effect exposes these OPTIONS

| Option | What it does | Impl for a renderer |
|---|---|---|
| **Intensity / Strength** | How strong the effect is. | Effect param (0–1) → filter arg. |
| **Speed / Frequency** | Rate of animated effects (flash, shake, glitch). | Time-scale on the effect's driving function. |
| **Scale / Size** | Effect element size (particles, frame). | Overlay scale. |
| **Position / Direction** | Where/which way it plays. | Overlay x/y / flow direction. |
| **Color / Hue** | Recolor the effect. | `hue`/tint on the effect layer. |
| **Opacity / Blend mode** | How it mixes with footage below. | `blend=all_mode=…` + alpha. |
| **Apply range (start/end)** | Timeline span the effect covers. | Enable filter only within `enable='between(t,a,b)'`. |
| **Keyframes** | Animate any of the above over time. | Keyframed effect params. |
| **Apply to main vs overlay** | Which track it affects. | Target selection in graph. |

### 11b. Video Effect categories (every category + its typical effects + how to build it)

> Named effects rotate/expand constantly and differ by version/region/Pro tier; the
> **categories and techniques** below are the stable, enumerable part.

| Category | Typical effects in it | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Trending / Hot** | rotating popular set (mixed of the below) | curated pack | mixed. |
| **Basic / Edit** | Zoom (punch-in), Shake (cam shake), Blur, Spin, Slide, Fade in/out, Mirror, Split-screen (2/3/4/6/9 grid), Pull-focus | transform + blur shaders; grid = tiled draws | `zoompan`, jittered `crop`, `gblur`, `rotate`, `hflip`/`vflip`, tiled `overlay`/`xstack`. |
| **Bling / Sparkle** | Glitter, Stars, Sparkle, Shine, Diamond | additive sprite/particle overlays | screen-blend PNG-sequence overlay (`blend=all_mode=screen`). |
| **Retro / Vintage / VHS** | VHS, Old TV, CRT scanlines, Tape wobble, Timestamp, Film grain, 8mm, Faded | curve + grain + channel offset + scanline texture | `curves`+`noise`+`rgbashift`+scanline overlay; wobble via `geq` displacement. |
| **Glitch / Distortion** | RGB/Chroma split, Digital glitch, Signal loss, Wave/Ripple, Pixelate, Liquify, Data-mosh | channel offset + block noise + UV displacement shaders | `rgbashift`/`chromashift`, `noise`, `pixelize`, `displace`/`geq`. |
| **Light / Lighting** | Light leaks, Lens flare, God rays, Bokeh, Flash, Strobe, Neon glow, Prism | screen-blend light textures; pulsing brightness | screen-blend overlays; strobe = `curves`/`eq` pulsed by `enable`/expr. |
| **Atmosphere / Particles** | Snow, Rain, Hearts, Petals, Bubbles, Dust, Confetti, Fireflies, Smoke, Sparks | particle systems as animated overlays | alpha/screen PNG-sequence overlays. |
| **Nature** | Sunlight, Clouds, Water ripple, Aurora, Rainbow | overlay + UV ripple | overlay + `geq` ripple displacement. |
| **Beauty / Face** | Soft glow, Blush, Sparkle eyes, Tears, Freckles | **face-landmark**-anchored overlays | ML face landmarks → masked overlay. |
| **Border / Frame** | Film border, Polaroid, Rounded corners, Colored frames, TV frame | overlay frame PNG / rounded-rect mask | overlay frame PNG, `pad`/`drawbox`, rounded via alpha mask. |
| **Textured** | Paper, Grunge, Dust & scratches, Grain, Fabric | multiply/overlay texture blend | overlay texture with `blend=all_mode=overlay/multiply`. |
| **3D / Motion** | 3D zoom (2.5D parallax on photos), Swing, Float, Bounce, Perspective | depth-based parallax / keyframed transform | keyframed transform; true parallax needs ML depth. |
| **Comic / Cartoon / Art** | Comic, Sketch, Oil paint, Halftone, Pop-art, Anime | stylization shaders / ML style transfer | ML style transfer; approx `edgedetect`+posterize (`lutrgb`/`curves`). |
| **Party / Music (beat-reactive)** | Beat flash, Equalizer bars, Pulse zoom, Color strobe | audio-envelope/beat-driven params | beat markers → keyframed `zoompan`/`eq` + bar overlays. |
| **Screen / Split / Trail** | Split-screen layouts, Freeze trail, Echo/Ghost trail, Motion blur trail | frame-history blending | `tblend`/`lagfun`/`tmix` for trails; grid layouts via `xstack`. |

### 11c. Body Effects (person-locked — need a segmentation mask)

| Effect | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Glow / Outline / Silhouette** | Colored edge or fill on the person. | **Person segmentation** mask → draw glow/outline along mask edge. | ML segmentation → edge of mask → colored stroke. |
| **Trails / Motion echo** | Ghost copies of the moving person. | Mask + blended frame history. | Segmentation + `lagfun`/`tmix` on masked layer. |
| **Wings / Halo / Aura / Lightning / Fire** | Elements attached around the body. | Mask anchors overlay elements. | Segmentation → position overlay relative to mask bbox. |
| **Clone / Twin** | Duplicate the person. | Cut out person, composite a second copy. | Segmentation → duplicate + offset overlay. |
| **Reshape (height/slim/muscle)** | Warp the body shape. | Mask + mesh warp. | ML pose/segmentation + warp mesh. |

### 11d. Photo/Image Effects (stills)

2.5D "3D photo" motion, parallax zoom, animated overlays, AI photo styles — same
techniques as above but keyframed on a single frame (Ken-Burns + depth parallax +
style transfer).

---

## 12. Stickers, elements & overlays

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Sticker/GIF library** | Animated/static graphics. | Sprite/APNG/Lottie layers with transform + keyframes. | Overlay PNG sequence / animated overlay. |
| **Custom stickers** | Cut out part of an image/frame as a sticker. | Manual/auto segmentation → RGBA cutout. | ML/manual mask → RGBA overlay. |
| **Shapes / callouts / progress bars** | Vector graphic elements. | Vector renderer (often Lottie/SVG-like). | Pre-rendered RGBA or drawbox/geq. |

---

## 13. AI / smart features (CapCut's headline differentiators)

| Feature | What it does | How CapCut implements it | Impl for a renderer |
|---|---|---|---|
| **Auto captions** | Transcribe speech to timed subtitles (see §9). | ASR model + timestamp alignment. | ML ASR. |
| **Auto reframe / smart crop** | Re-target aspect ratio (e.g., 16:9→9:16) keeping the subject in frame. | **Subject/saliency detection** per frame → crop window that follows the subject, smoothed. | ML saliency/detection → keyframed `crop`. |
| **Background removal (auto cutout)** | Remove background from people without green screen. | **Semantic/portrait segmentation** (MODNet/U²-Net-style) → per-frame alpha matte. | ML matting model → `alphamerge`/overlay. |
| **Long video → shorts / highlights** | Auto-pick highlight clips from long footage. | ASR + scene/silence detection + engagement heuristics select segments. | ML + scene/silence detection (`silencedetect`, scene score). |
| **AI body / retouch / reshape** | Smooth skin, slim, enlarge eyes, brighten, teeth whiten. | Face landmarks → mesh warp + bilateral skin smoothing. | ML landmarks + warp + `smartblur`/bilateral. |
| **Relight / studio light** | Add virtual lighting to a face. | Normal/depth estimation → relighting shader. | ML depth/normal + shader. |
| **Enhance / upscale / sharpen** | Increase resolution/clarity. | **Super-resolution** CNN. | ML SR (Real-ESRGAN-class); fallback `scale`+`unsharp`. |
| **Video stabilization (anti-shake)** | Smooth handheld shake. | Feature tracking → estimate camera path → smooth → warp/crop. | FFmpeg `vidstabdetect`+`vidstabtransform` (2-pass) or `deshake`. |
| **Motion tracking** | Attach text/sticker/mask/mosaic to a moving object. | Object tracker (correlation/optical-flow, or ML) outputs per-frame position/scale → drives a layer's keyframes. | ML/optical-flow tracker → keyframes. |
| **AI script / text-to-video** | Generate an edit from a prompt/script. | LLM writes script → TTS + stock matching + auto-captions assemble a timeline. | LLM + TTS + asset pipeline. |
| **AI image/video generation & style transfer** | Generate or restyle footage (cartoon, anime, etc.). | Diffusion/GAN generative or per-frame style-transfer models. | ML generative models. |
| **Voice isolation / denoise / vocal split** | Clean or separate audio (see §10). | Source-separation / denoise ML. | ML. |
| **Auto color / auto-adjust** | One-tap correction. | Histogram analysis → adjust params. | `signalstats`→`eq`/`curves`. |

---

## 14. Templates & one-tap creation

A template is a **fully-designed, serialized timeline with empty media slots**: the
cuts, transitions, effects, text, and beat-synced music are already authored; the
user just drops clips/photos into the slots and the timings/effects are preserved.

### 14a. Template options (what the user can control per template)

| Option | What it does | Impl for a renderer |
|---|---|---|
| **Clip/photo count** | Fixed number of media slots required (e.g., "9 clips"). | Slot list length in template schema. |
| **Per-slot duration** | Each slot has a fixed length the media is trimmed to. | Clamp/trim user media to slot duration. |
| **Slot type** | Video, photo, or text slot. | Slot `type` field. |
| **Editable text** | Which on-screen text the user may change. | `editable:true` on text nodes. |
| **Replaceable music** | Swap the bundled track (may lose beat-sync). | Music node flag + re-run beat detection. |
| **Aspect ratio** | Locked canvas (usually 9:16). | Canvas size in template. |
| **Trim inside slot** | Choose which part of your clip fills the slot. | Per-slot in/out offset. |

### 14b. Template categories (the "types" available)

> Categories vary by region/trend; these are the stable buckets.

| Category | What it's for | Typical structure |
|---|---|---|
| **Trending / For You** | Current viral formats. | short beat-synced cuts + trendy effects. |
| **Photo / Slideshow** | Photos into a montage. | photo slots + Ken-Burns + transitions. |
| **Beat / Music sync** | Cuts land on the beat. | slots aligned to beat markers. |
| **Vlog** | Day-in-the-life edits. | clip slots + captions + subtle grade. |
| **Intro / Outro** | Channel bumpers. | logo/text animation slots. |
| **Aesthetic / Mood** | Style-forward looks. | heavy filter + overlay + text. |
| **Birthday / Anniversary / Love** | Occasion edits. | themed stickers + text + music. |
| **Travel** | Trip recaps. | fast cuts + location text + transitions. |
| **Business / Promo / Marketing** | Product/brand clips. | text callouts + logo + CTA. |
| **Food** | Recipe/restaurant. | close-up slots + warm filter. |
| **Fashion / OOTD** | Outfit reveals. | beat cuts + zoom effects. |
| **Gaming** | Highlights/montage. | fast cuts + glitch/impact effects. |
| **Meme / Funny** | Reaction/meme formats. | text-top/bottom + zoom-punch + SFX. |
| **Text / News** | Caption-driven. | text blocks + lower-thirds. |
| **3D / 2.5D photo** | Photo with parallax motion. | single photo + depth parallax. |
| **Countdown / Seasonal** | Holidays, events. | themed overlays + timer. |

### 14c. How to implement a template engine

1. **Template schema (JSON):** a serialized timeline — ordered `slots[]` each with
   `{type, duration, transform-keyframes, effects[], transition-in, filter, text?}`,
   plus an `audio` track with precomputed `beatMarkers[]`, and a `canvas` (ratio/size).
2. **Slot binding:** user selects N media → bind to slots in order → for each,
   trim/clamp to the slot's fixed duration (optional user in/out offset).
3. **Beat sync:** slot boundaries and effect triggers reference beat timestamps, so
   swapping music re-runs onset detection (§10) and re-snaps.
4. **Editable flags:** nodes marked `editable` (text, sometimes music) are exposed;
   everything else is locked.
5. **Compile:** the filled template compiles to the **same FFmpeg filtergraph** the
   normal editor emits (`concat` + `xfade` + `overlay` + `drawtext` + effects), so
   templates need no separate renderer — just a filler + the schema.

Auto-cut / "highlight" templates additionally run beat detection + a preset
cut/effect pattern to build the slot layout automatically from selected media.

---

## Implementation architecture notes (how CapCut runs it all in real time)

- **Non-destructive model:** the project is a JSON-like scene graph (tracks → clips
  → effects/keyframes). Nothing is baked until export. Every "edit" mutates
  parameters, not pixels.
- **GPU compositor:** each frame is rendered by walking the graph bottom-up: decode
  source frame → apply per-clip filters (shaders) → apply transform → composite with
  blend mode → draw text/stickers → apply adjustment/effect layers. Uses OpenGL
  ES/Metal on device; Skia for vector/text.
- **Effects/filters = shaders:** transitions, effects, blend modes, chroma key,
  masks, and LUT filters are all fragment shaders parameterized by time + slider
  uniforms, which is why they preview in real time.
- **Filters = 3D LUTs:** the "Filters" tab is mostly `.cube` LUT sampling — cheap and
  consistent (the same technique as FFmpeg `lut3d`).
- **Keyframes = interpolators:** an animation system evaluates each animatable
  parameter at the current time (linear/Bézier easing) and feeds the value into the
  render pass.
- **AI = separate model inference:** captions (ASR), matting (segmentation),
  tracking, reframe (saliency/detection), enhance (super-resolution), retouch
  (landmarks) run as ML models producing data (text, masks, coordinates) that the
  render graph then consumes — the models don't render pixels directly (except
  generative/style-transfer ones).
- **Proxies for editing:** low-res proxy media for smooth scrubbing; full-res only at
  export.
- **Hardware codecs:** decode/encode via platform hardware (MediaCodec / VideoToolbox
  / NVENC) to hit real-time.

---

## Priority map for an FFmpeg-based Shorts renderer (this project)

Highest value / most feasible **without ML**, roughly in order:

1. Cuts/trim/split + multi-clip concat (`concat`, timeline model).
2. Speed + curve ramping (`setpts`/`atempo`; interpolation already present).
3. Transitions (`xfade`).
4. Text & burned captions (`drawtext`/`subtitles`), from an external `.srt`.
5. Overlays/PiP + transform + blend modes (`overlay`,`scale`,`rotate`,`blend`).
6. Color/adjust + LUT filters (`eq`,`curves`,`lut3d`).
7. Audio: volume/fades/ducking/denoise (`volume`,`afade`,`sidechaincompress`,`afftdn`).
8. Ken Burns / zoom-pan (`zoompan`), masks (`maskedmerge`), chroma key (`chromakey`).
9. Stabilization (`vidstab`).

Requires **ML models** (bigger lift): auto captions (ASR), background removal
(matting), auto-reframe (saliency), motion tracking, upscale/enhance, retouch, TTS,
generative/style effects, vocal separation.
