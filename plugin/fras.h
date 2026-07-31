#ifndef FRAS_API_H
#define FRAS_API_H

#include <stdint.h>
#include <stddef.h>
#include <limits.h>

typedef float Sample;
typedef uint64_t Offset;
typedef uint16_t VoiceId;
typedef uint8_t Note;
typedef uint8_t Velocity;

#define ALL_VOICES UINT16_MAX

typedef enum
{
    EV_NOTE_ON,
    EV_NOTE_OFF,
    EV_PARAM_SET,
    EV_CUSTOM
} EventKind;

typedef struct
{
    Offset offset;
    VoiceId voice;

    EventKind kind;

    union
    {
        struct { Note num; Velocity velocity; } note;
        struct { uint32_t id; float value; } param;
        struct { uint32_t id; uint8_t *blob; size_t len; } custom;
    };
} Event;

typedef void* InstrumentHandle;
typedef InstrumentHandle (*InstrumentInit)(uint32_t id, uint32_t sample_rate);
typedef void (*InstrumentDestroy)(InstrumentHandle);
typedef void (*InstrumentHandleEvent)(InstrumentHandle, Event);
typedef void (*InstrumentRender)(InstrumentHandle, Sample *, size_t);

typedef struct {
    InstrumentInit init;
    InstrumentDestroy destroy;
    InstrumentHandleEvent handle_event;
    InstrumentRender render;
} InstrumentVTable;

const extern InstrumentVTable instrument_vtable;
const extern uint32_t fras_major_version;

#endif
