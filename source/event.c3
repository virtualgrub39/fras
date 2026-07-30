module fras::event @public;

import fras::types;

enum EventKind : uint
{
	NOTE_ON,
	NOTE_OFF,
	PARAM_SET,
	CUSTOM,
}

struct Event
{
	Offset offset;
	VoiceId voice;

	EventKind kind;

	union
	{
		struct note { Note num; Velocity velocity; }
		struct param { uint id; float value; }
		struct custom { uint id; char *blob; usz len; }
	}
}

fn Event note_on (Offset offset, VoiceId voice, Note note, Velocity velocity)
{
	return {
		.kind = NOTE_ON,
		.offset = offset,
		.voice = voice,
		.note.num = note,
		.note.velocity = velocity,
	};
}

fn Event note_off (Offset offset, VoiceId voice)
{
	return {
		.kind = NOTE_OFF,
		.offset = offset,
		.voice = voice,
	};
}

fn Event param_set (Offset offset, VoiceId voice, uint id, float value)
{
	return {
		.kind = PARAM_SET,
		.offset = offset,
		.voice = voice,
		.param.id = id,
		.param.value = value,
	};
}

fn Event custom (Offset offset, VoiceId voice, uint id, char[] blob)
{
	return {
		.kind = CUSTOM,
		.offset = offset,
		.voice = voice,
		.custom.id = id,
		.custom.blob = blob.ptr,
		.custom.len = blob.len,
	};
}
