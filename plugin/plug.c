#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "fras.h"

#define PARAM_ATTACK 0
#define PARAM_RELEASE 1

typedef enum
{
    IDLE,
    ATTACK,
    SUSTAIN,
    RELEASE,
} VoiceState;

typedef struct
{
    uint32_t sample_rate;

    VoiceState state;
    Note note;
    Velocity velocity;
    float phase;

    float env;
    float attack_rate;
    float release_rate;
} Voice;

void *
instrument_init (uint32_t id, uint32_t sample_rate)
{
    printf ("[DEBUG] instrument_init(%d, %d)\n", id, sample_rate);
    (void) id;

    Voice *voice = calloc (1, sizeof *voice);

    voice->sample_rate = sample_rate;
    voice->state = IDLE;

    voice->attack_rate = 1.0 / (0.010 * sample_rate);
    voice->release_rate = 1.0 / (0.100 * sample_rate);

    return voice;
}

void
voice_trigger (Voice *voice, Note note, Velocity velocity)
{
    voice->note= note;
    voice->velocity = velocity;
    voice->phase = 0;
    voice->state = ATTACK;
    voice->env = 0.0f;
}

void
voice_release (Voice *voice)
{
    if (voice->state != IDLE) voice->state = RELEASE; 
}

void
voice_set_param (Voice *voice, uint32_t id, float value)
{
    printf("[DEBUG] PARAM %d = %f\n", id, value);

    switch (id)
    {
    case PARAM_ATTACK: {
        float secs = value / 1000.0;
        secs = (secs < 0.001) ? 0.001 : secs;
        voice->attack_rate = 1.0 / (secs * voice->sample_rate);
    }
    break;
    case PARAM_RELEASE: {
        float secs = value / 1000.0;
        secs = (secs < 0.001) ? 0.001 : secs;
        voice->release_rate = 1.0 / (secs * voice->sample_rate);
    }
    break;
    default: break;
    }
}

void
instrument_handle_event (InstrumentHandle instrument, Event ev)
{
    printf ("[DEBUG] instrument_handle_event(%lu, %d, %d)\n", ev.offset, ev.voice, ev.kind);
    Voice *voice = instrument;

    switch (ev.kind)
    {
    case EV_NOTE_ON:
        voice_trigger (voice, ev.note.num, ev.note.velocity);
        break;
    case EV_NOTE_OFF:
        voice_release (voice);
        break;
    case EV_PARAM_SET:
        voice_set_param (voice, ev.param.id, ev.param.value);
        break;
    default: break;
    }
}

void
instrument_render (InstrumentHandle instrument, Sample *packet, size_t len)
{
    Voice *voice = instrument;
    if (voice->state == IDLE) return;

    float freq = 440.0 * exp2f((voice->note - 69.0) / 12.0);
    float phase_inc = freq / voice->sample_rate;

    for (size_t i = 0; i < len; ++i)
    {
        switch (voice->state)
        {
        case ATTACK:
            voice->env += voice->attack_rate;
            if (voice->env >= 1.0)
            {
                voice->env = 1.0;
                voice->state = SUSTAIN;
            }
            break;
        case SUSTAIN: break;
        case RELEASE:
            voice->env -= voice->release_rate;
            if (voice->env <= 0.0)
            {
                voice->env = 0.0;
                voice->state = IDLE;
                break;
            }
            break;
        case IDLE: break;
        }

        packet[i] += sinf (voice->phase * 2 * M_PI) * (voice->velocity / 255.0 * voice->env);
        voice->phase += phase_inc;
        if (voice->phase >= 1.0) voice->phase -= 1.0;
    }
}

void 
instrument_destroy (InstrumentHandle voice)
{
    printf ("[DEBUG] instrument_destroy()\n");
    free (voice);
}

static const InstrumentVTable VTABLE = {
    .init = instrument_init,
    .destroy = instrument_destroy,
    .handle_event = instrument_handle_event,
    .render = instrument_render,
};

const InstrumentVTable *
instrument_vtable ()
{
    return &VTABLE;
}
