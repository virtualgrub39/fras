module fras::router;

import fras;

import std::math;

struct Config
{
	uint sample_rate;
	VoiceId voice_count;
	usz packet_sz;
}

struct Router <EVENT_QUEUE_SZ>
{
	Config config;

	instrument::Slot[] voices;

	Queue {Event, EVENT_QUEUE_SZ} evq;
	ulong offset;
}

fn void? Router.init (Router *r, Config* cfg)
{
	r.config = *cfg;
	r.voices = mem::new_array(instrument::Slot, cfg.voice_count);
}

fn void Router.assign_voice (Router *r, VoiceId voice, Plugin *p)
{
	if (voice == types::ALL_VOICES)
	{
		foreach (i, &slot : r.voices)
			slot.assign (p, (uint) i, r.config.sample_rate);
	}
	else
	{
		instrument::Slot *slot = &r.voices[voice];
		slot.assign (p, (uint) voice, r.config.sample_rate);
	}
}

fn void Router.deinit (Router *r)
{
	foreach (&slot : r.voices)
		slot.release ();

	mem::free (r.voices.ptr);
}

fn void? Router.ev_push (Router *r, Event ev)
{
	r.evq.enqueue(ev)!;
}

fn void Router.ev_dispatch (Router *r, Event ev)
{
	if (ev.voice == types::ALL_VOICES)
	{
		foreach (&slot : r.voices) slot.plugin.callbacks.handle_event (slot.state, ev);
	}
	else 
	{
		instrument::Slot *slot = &r.voices[ev.voice];
		slot.plugin.callbacks.handle_event (slot.state, ev);
	}
}

fn void Router.render (Router *r, Sample[] packet)
{
	packet[..] = 0;

	usz packet_count = (usz) math::ceil ((float)packet.len / (float)r.config.packet_sz);

	for (usz i = 0; i < packet_count; ++i)
    {
        usz offset = i * r.config.packet_sz;
        usz packet_sz = math::min ((usz) r.config.packet_sz, (usz) (packet.len - offset));
        
        while (try Event *front = r.evq.front())
        {
            if (front.offset > r.offset) break;
            r.ev_dispatch (r.evq.dequeue()!!);
        }

		foreach (&slot : r.voices)
			slot.plugin.callbacks.render (slot.state, packet.ptr + offset, packet_sz);

        r.offset += packet_sz;
    }
}
