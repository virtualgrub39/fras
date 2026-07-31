#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "fras.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* Parameter IDs */
#define PARAM_ATTACK      0  /* Attack time in ms */
#define PARAM_RELEASE     1  /* Release time in ms */
#define PARAM_ROOT_NOTE   2  /* MIDI Root note of sample (0-127) */
#define PARAM_LOOP_ENABLE 3  /* 0 = off, 1 = loop on */

#define CUSTOM_LOAD_SAMPLE 0 /* Load PCM float array */

typedef enum
{
    STATE_IDLE,
    STATE_ATTACK,
    STATE_SUSTAIN,
    STATE_RELEASE
} VoiceState;

typedef struct
{
    uint32_t sample_rate;

    VoiceState state;
    Note note;
    Velocity velocity;

    double pos;      /* Fractional playhead position */
    double pos_inc;  /* Playback speed step based on pitch */

    float env;
    float attack_ms;
    float release_ms;
    float attack_rate;
    float release_rate;

    Sample *sample_buffer;
    size_t sample_len;
    Note root_note;
    int loop_enable;
} SingleVoiceSynth;

static void
update_envelope_rates(SingleVoiceSynth *synth)
{
    float att_sec = (synth->attack_ms < 1.0f) ? 0.001f : (synth->attack_ms / 1000.0f);
    float rel_sec = (synth->release_ms < 1.0f) ? 0.001f : (synth->release_ms / 1000.0f);

    synth->attack_rate = 1.0f / (att_sec * (float)synth->sample_rate);
    synth->release_rate = 1.0f / (rel_sec * (float)synth->sample_rate);
}

static void
generate_default_sample(SingleVoiceSynth *synth)
{
    synth->sample_len = synth->sample_rate;
    synth->sample_buffer = malloc(synth->sample_len * sizeof(Sample));
    synth->root_note = 60; /* C4 */

    if (!synth->sample_buffer) return;

    for (size_t i = 0; i < synth->sample_len; ++i)
    {
        float t = (float)i / (float)synth->sample_rate;
        float decay = expf(-3.0f * t);
        
        float fundamental = sinf(2.0f * M_PI * 261.63f * t);
        float harmonic2   = 0.5f * sinf(2.0f * M_PI * 523.25f * t);
        float harmonic3   = 0.25f * sinf(2.0f * M_PI * 784.88f * t);

        synth->sample_buffer[i] = (fundamental + harmonic2 + harmonic3) * decay * 0.4f;
    }
}

InstrumentHandle
instrument_init(uint32_t id, uint32_t sample_rate)
{
    (void)id;
    SingleVoiceSynth *synth = calloc(1, sizeof(SingleVoiceSynth));
    if (!synth) return NULL;

    synth->sample_rate = sample_rate;
    synth->state = STATE_IDLE;
    synth->attack_ms = 10.0f;
    synth->release_ms = 150.0f;
    synth->loop_enable = 0;

    update_envelope_rates(synth);
    generate_default_sample(synth);

    return (InstrumentHandle)synth;
}

void
instrument_destroy(InstrumentHandle handle)
{
    SingleVoiceSynth *synth = (SingleVoiceSynth *)handle;
    if (!synth) return;

    if (synth->sample_buffer) free(synth->sample_buffer);
    free(synth);
}

void
instrument_handle_event(InstrumentHandle handle, Event ev)
{
    SingleVoiceSynth *synth = (SingleVoiceSynth *)handle;
    if (!synth) return;

    switch (ev.kind)
    {
    case EV_NOTE_ON:
    {
        synth->note = ev.note.num;
        synth->velocity = ev.note.velocity;
        synth->pos = 0.0;

        double pitch_semitones = (double)ev.note.num - (double)synth->root_note;
        synth->pos_inc = pow(2.0, pitch_semitones / 12.0);

        synth->state = STATE_ATTACK;
        synth->env = 0.0f;
        break;
    }

    case EV_NOTE_OFF:
        if (synth->state != STATE_IDLE)
        {
            synth->state = STATE_RELEASE;
        }
        break;

    case EV_PARAM_SET:
        switch (ev.param.id)
        {
        case PARAM_ATTACK:
            synth->attack_ms = ev.param.value;
            update_envelope_rates(synth);
            break;
        case PARAM_RELEASE:
            synth->release_ms = ev.param.value;
            update_envelope_rates(synth);
            break;
        case PARAM_ROOT_NOTE:
            synth->root_note = (Note)ev.param.value;
            break;
        case PARAM_LOOP_ENABLE:
            synth->loop_enable = (ev.param.value >= 0.5f) ? 1 : 0;
            break;
        default:
            break;
        }
        break;

    case EV_CUSTOM:
        if (ev.custom.id == CUSTOM_LOAD_SAMPLE && ev.custom.blob && ev.custom.len > 0)
        {
            size_t sample_count = ev.custom.len / sizeof(Sample);
            Sample *new_buf = malloc(ev.custom.len);

            if (new_buf)
            {
                memcpy(new_buf, ev.custom.blob, ev.custom.len);
                if (synth->sample_buffer) free(synth->sample_buffer);

                synth->sample_buffer = new_buf;
                synth->sample_len = sample_count;
                synth->state = STATE_IDLE;
            }
        }
        break;

    default:
        break;
    }
}

void
instrument_render(InstrumentHandle handle, Sample *packet, size_t len)
{
    SingleVoiceSynth *synth = (SingleVoiceSynth *)handle;
    if (synth->state == STATE_IDLE || !synth->sample_buffer || synth->sample_len == 0)
    {
        return;
    }

    for (size_t i = 0; i < len; ++i)
    {
        switch (synth->state)
        {
        case STATE_ATTACK:
            synth->env += synth->attack_rate;
            if (synth->env >= 1.0f)
            {
                synth->env = 1.0f;
                synth->state = STATE_SUSTAIN;
            }
            break;

        case STATE_SUSTAIN:
            break;

        case STATE_RELEASE:
            synth->env -= synth->release_rate;
            if (synth->env <= 0.0f)
            {
                synth->env = 0.0f;
                synth->state = STATE_IDLE;
                return;
            }
            break;

        case STATE_IDLE:
            return;
        }

        size_t i0 = (size_t)synth->pos;
        size_t i1 = i0 + 1;
        float frac = (float)(synth->pos - i0);

        if (i0 >= synth->sample_len)
        {
            if (synth->loop_enable && synth->sample_len > 0)
            {
                synth->pos = fmod(synth->pos, (double)synth->sample_len);
                i0 = (size_t)synth->pos;
                i1 = (i0 + 1) % synth->sample_len;
                frac = (float)(synth->pos - i0);
            }
            else
            {
                synth->state = STATE_IDLE;
                synth->env = 0.0f;
                return;
            }
        }
        else if (i1 >= synth->sample_len)
        {
            i1 = synth->loop_enable ? 0 : i0;
        }

        Sample s0 = synth->sample_buffer[i0];
        Sample s1 = synth->sample_buffer[i1];
        Sample sample_val = (1.0f - frac) * s0 + frac * s1;

        float vel_scale = (float)synth->velocity / 255.0f;
        packet[i] += sample_val * synth->env * vel_scale;

        synth->pos += synth->pos_inc;
    }
}

const InstrumentVTable instrument_vtable = {
    .init = instrument_init,
    .destroy = instrument_destroy,
    .handle_event = instrument_handle_event,
    .render = instrument_render,
};

const uint32_t fras_major_version = 0;
