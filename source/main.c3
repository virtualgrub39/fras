import fras;

import std::io;

const uint PARAM_ATTACK = 0;
const uint PARAM_RELEASE = 1;

fn void main () => @pool() {
	const usz F0 = 44100;

	RouterConfig cfg = {
		.instrument_path = "plug.so",
		.packet_sz = 512,
		.sample_rate = F0,
		.voice_count = 4
	};

	Router{16} r;
	if (catch e = r.init(&cfg))
	{
		io::printfn ("Failed to initialize router: %s", e);
		return;
	}

	r.ev_push(event::param_set (0, types::ALL_VOICES, PARAM_ATTACK, 100))!!;
	r.ev_push(event::note_on (0, 0, 60, 80))!!;
	r.ev_push(event::note_on (11025, 1, 63, 80))!!;
	r.ev_push(event::note_on (22050, 2, 67, 80))!!;
	r.ev_push(event::note_off (33075, 1))!!;
	r.ev_push(event::param_set (44100, types::ALL_VOICES, PARAM_RELEASE, 700))!!;
	r.ev_push(event::note_off (44100, 0))!!;
	r.ev_push(event::note_off (52000, 2))!!;

	const BUFFER_SZ = F0 * 2;
	Sample* buffer = tmalloc(float::size * BUFFER_SZ);
	
	Sample[] packet = buffer[0 : BUFFER_SZ];
	r.render (packet);

	r.deinit ();

	file::save("out.raw", ((char*)buffer)[0 : BUFFER_SZ * float::size])!!;
}
