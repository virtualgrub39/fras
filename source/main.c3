import fras;

import std::io;
import sdl3;

const uint PARAM_ATTACK = 0;
const uint PARAM_RELEASE = 1;

const usz PACKET_SZ = 512;

struct AudioCtx
{
    Router{16} *router;
}

float[PACKET_SZ] g_carry;
usz g_carry_pos = 0;
usz g_carry_len = 0;

fn void audio_cb (void *user, sdl3::SdlAudioStream *stream, int additional, int total)
{
    AudioCtx *ctx = user;

    usz samples_needed = (usz)additional / float::size;
    usz written = 0;

    while (written < samples_needed)
    {
        if (g_carry_pos == g_carry_len)
        {
            float[] pkt = &g_carry;
            ctx.router.render(pkt);
            g_carry_pos = 0;
            g_carry_len = PACKET_SZ;
        }

        usz avail = g_carry_len - g_carry_pos;
        usz take = (samples_needed - written) < avail ? (samples_needed - written) : avail;

        sdl3::putAudioStreamData(stream, &g_carry[g_carry_pos], (int)(take * float::size));

        g_carry_pos += take;
        written += take;
    }
}

fn int map_key (sdl3::SdlKeycode key)
{
    switch (key)
    {
        case KEY_A: return 0;  // C
        case KEY_W: return 1;  // C#
        case KEY_S: return 2;  // D
        case KEY_E: return 3;  // D#
        case KEY_D: return 4;  // E
        case KEY_F: return 5;  // F
        case KEY_T: return 6;  // F#
        case KEY_G: return 7;  // G
        case KEY_Y: return 8;  // G#
        case KEY_H: return 9;  // A
        case KEY_U: return 10; // A#
        case KEY_J: return 11; // B
    }
    return -1;
}

fn int get_note_from_xy (float x, float y)
{
    // Black keys hitboxes (checked first because they overlap white keys)
    if (y < 150.0)
    {
        if (x >= 70.0 && x <= 130.0) return 1;
        if (x >= 170.0 && x <= 230.0) return 3;
        if (x >= 370.0 && x <= 430.0) return 6;
        if (x >= 470.0 && x <= 530.0) return 8;
        if (x >= 570.0 && x <= 630.0) return 10;
    }

    // White keys hitboxes
    if (x >= 0.0 && x < 100.0) return 0;
    if (x >= 100.0 && x < 200.0) return 2;
    if (x >= 200.0 && x < 300.0) return 4;
    if (x >= 300.0 && x < 400.0) return 5;
    if (x >= 400.0 && x < 500.0) return 7;
    if (x >= 500.0 && x < 600.0) return 9;
    if (x >= 600.0 && x <= 700.0) return 11;

    return -1;
}

fn void trigger_note (Router{16} *r, bool[] active_notes, int note, bool is_on)
{
    if (note < 0 || note > 11) return;
    if (active_notes[note] == is_on) return;

    active_notes[note] = is_on;

    types::VoiceId voice = (types::VoiceId)note;
    
    if (is_on)
    {
        types::Note midi_note = (types::Note)(60 + note); // 60 is Middle C
        r.ev_push(event::note_on(0, voice, midi_note, 64))!!;
    }
    else
    {
        r.ev_push(event::note_off(0, voice))!!;
    }
}

struct BlackKeyDef { int note; float x; }

fn void main () => @pool()
{
    const usz F0 = 44100;

    sdl3::init({.audio, .video});
    defer sdl3::quit();

    sdl3::SdlWindow *window = sdl3::createWindow("fras keyboard demo", 700, 250, { .input_focus });
    if (!window)
    {
        sdl3::log ("Couldn't create window: %s\n", sdl3::getError());
        return;
    }
    defer sdl3::destroyWindow (window);

    sdl3::SdlRenderer *renderer = sdl3::createRenderer(window, null);
    defer sdl3::destroyRenderer(renderer);

    Plugin *demo_synth = instrument::plugin_load ("./plug.so")!!;
    defer instrument::plugin_unload (demo_synth);

    router::Config cfg = {
        .packet_sz = PACKET_SZ,
        .sample_rate = F0,
        .voice_count = 12 
    };

    Router{16} r;
    if (catch e = r.init(&cfg))
    {
        io::printfn ("Failed to initialize router: %s", e);
        return;
    }
    defer r.deinit();

    r.assign_voice (types::ALL_VOICES, demo_synth);



    AudioCtx ctx = { .router = &r };

    sdl3::SdlAudioSpec spec = { .format = sdl3::SdlAudioFormat.F32, .channels = 1, .freq = F0 };
    sdl3::SdlAudioStream *stream = sdl3::openAudioDeviceStream (sdl3::AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, &audio_cb, &ctx);
    defer sdl3::destroyAudioStream (stream);
    sdl3::resumeAudioStreamDevice (stream);

    bool running = true;
    bool[12] active_notes;
    int mouse_active_note = -1;

    int[7] white_keys = { 0, 2, 4, 5, 7, 9, 11 };
    BlackKeyDef[5] black_keys = { {1, 70.0f}, {3, 170.0f}, {6, 370.0f}, {8, 470.0f}, {10, 570.0f} };

    while (running)
    {
        sdl3::SdlEvent e;
        while (sdl3::pollEvent(&e))
        {
            switch (e.type)
            {
                case QUIT:
                    running = false;
                    break;
                case KEY_DOWN:
                case KEY_UP:
                {
                    int note = map_key(e.key.key);
                    trigger_note(&r, &active_notes, note, e.type == KEY_DOWN);
                    break;
                }
                case MOUSE_BUTTON_DOWN:
                {
                    mouse_active_note = get_note_from_xy(e.button.x, e.button.y);
                    trigger_note(&r, &active_notes, mouse_active_note, true);
                    break;
                }
                case MOUSE_BUTTON_UP:
                {
                    if (mouse_active_note != -1)
                    {
                        trigger_note(&r, &active_notes, mouse_active_note, false);
                        mouse_active_note = -1;
                    }
                    break;
                }
                case MOUSE_MOTION:
                {
                    if (mouse_active_note != -1)
                    {
                        int hover = get_note_from_xy(e.motion.x, e.motion.y);
                        if (hover != mouse_active_note && hover != -1)
                        {
                            trigger_note(&r, &active_notes, mouse_active_note, false);
                            trigger_note(&r, &active_notes, hover, true);
                            mouse_active_note = hover;
                        }
                    }
                    break;
                }
            }
        }

        sdl3::setRenderDrawColor(renderer, 50, 50, 50, 255);
        sdl3::renderClear(renderer);

        for (int i = 0; i < 7; i++)
        {
            int note = white_keys[i];
            sdl3::SdlFRect rect = { .x = (float)(i * 100 + 1), .y = 1.0f, .w = 98.0f, .h = 248.0f };
            
            if (active_notes[note])
			{
				sdl3::setRenderDrawColor(renderer, 200, 200, 200, 255);
			}
            else
			{
				sdl3::setRenderDrawColor(renderer, 255, 255, 255, 255);
			}
            
            sdl3::renderFillRect(renderer, &rect);
        }

        for (int i = 0; i < 5; i++)
        {
            int note = black_keys[i].note;
            sdl3::SdlFRect rect = { .x = black_keys[i].x, .y = 0.0f, .w = 60.0f, .h = 150.0f };
            
            if (active_notes[note])
			{
				sdl3::setRenderDrawColor(renderer, 100, 100, 100, 255);
			}
            else
			{
				sdl3::setRenderDrawColor(renderer, 30, 30, 30, 255);
			}
            
            sdl3::renderFillRect(renderer, &rect);
        }

        sdl3::renderPresent(renderer);
    }
}
