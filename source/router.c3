module fras::router;

import fras;

import libc;
import std::math;

struct RouterConfig
{
	uint sample_rate;
	VoiceId voice_count;
	usz packet_sz;
	String instrument_path;
}

struct Router <EVENT_QUEUE_SZ>
{
	RouterConfig config;

	InstrumentHandle[] instruments;
	InstrumentVTable callbacks;
	void *plug_handle;

	Queue {Event, EVENT_QUEUE_SZ} evq;
	ulong offset;
}

faultdef DLERROR;

fn void? Router.init (Router *r, RouterConfig* cfg)
{
	r.config = *cfg;

	@pool() {
		r.plug_handle = libc::dlopen(cfg.instrument_path.zstr_tcopy(), libc::RTLD_NOW);
		if (!r.plug_handle) return DLERROR~;

		void *sym = libc::dlsym (r.plug_handle, "instrument_vtable");
		if (!sym) return DLERROR~;
		InstrumentGetVTable getter = (InstrumentGetVTable)sym;

		r.callbacks = *getter();
	};

	r.instruments = mem::new_array(InstrumentHandle, cfg.voice_count);
	foreach (i, &instrument : r.instruments)
		*instrument = r.callbacks.init((uint)i, cfg.sample_rate);
}

fn void Router.deinit (Router *r)
{
	foreach (instrument : r.instruments)
		r.callbacks.destroy(instrument);
	mem::free(r.instruments.ptr);
	libc::dlclose(r.plug_handle);
}

fn void? Router.ev_push (Router *r, Event ev)
{
	r.evq.enqueue(ev)!;
}

fn void Router.ev_dispatch (Router *r, Event ev)
{
	if (ev.voice == types::ALL_VOICES)
	{
		foreach (instr : r.instruments) r.callbacks.handle_event(instr, ev);
	}
	else if (ev.voice < r.config.voice_count)
	{
		r.callbacks.handle_event (r.instruments[ev.voice], ev);
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

		foreach (instr : r.instruments)
			r.callbacks.render (instr, packet.ptr + offset, packet_sz);

        r.offset += packet_sz;
    }
}
