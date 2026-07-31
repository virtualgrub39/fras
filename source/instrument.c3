module fras::instrument;
import fras;
import libc;

alias Handle = void*;

alias Init = fn Handle (uint id, uint sample_rate);
alias Destroy = fn void (Handle);
alias HandleEvent = fn void (Handle, Event);
alias Render = fn void (Handle, Sample *, usz);

const API_VERSION = 0;

struct VTable
{
    Init init;
    Destroy destroy;
    HandleEvent handle_event;
    Render render;
}

struct Plugin
{
    Handle handle;
    VTable callbacks;
}

struct Slot
{
    Plugin *plugin;
    Handle state;
}

faultdef DLOPEN_FAILED, DLSYM_FAILED, WRONG_API_VERSION;

fn Plugin*? plugin_load (String path)
{
    Handle handle = null;
    @pool() {
        handle = libc::dlopen (path.zstr_tcopy(), libc::RTLD_NOW);
    };
    if (!handle) return DLOPEN_FAILED~;

    void *sym = libc::dlsym (handle, "instrument_vtable");
    if (!sym) 
    {
        libc::dlclose (handle);
        return DLSYM_FAILED~;
    }
	VTable callbacks = *(VTable*)sym;

	sym = libc::dlsym (handle, "fras_major_version");
	if (!sym)
	{
		libc::dlclose (handle);
		return DLSYM_FAILED~;
	}
	uint version = *(uint*)sym;
	if (version != API_VERSION)
	{
		libc::dlclose (handle);
		return WRONG_API_VERSION~;
	}

    Plugin *p = mem::new (Plugin);
    p.handle = handle;
    p.callbacks = callbacks;

    return p;
}

fn void plugin_unload (Plugin *p)
{
    if (p == null) return;
    if (p.handle != null) libc::dlclose (p.handle);
    mem::free (p);
}

fn void Slot.assign (Slot *slot, Plugin *p, uint voice, uint sample_rate)
{
    if (slot.state != null && slot.plugin != null)
    {
        slot.plugin.callbacks.destroy (slot.state);
    }

    slot.plugin = p;
    slot.state = p.callbacks.init (voice, sample_rate);
}

fn void Slot.release (Slot *slot)
{
    if (slot.state != null && slot.plugin != null)
    {
        slot.plugin.callbacks.destroy (slot.state);
        slot.state = null;
    }
}
