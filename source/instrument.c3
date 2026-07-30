module fras::instrument;

import fras::event, fras::types;

alias InstrumentHandle = void*;

alias InstrumentInit = fn InstrumentHandle (uint id, uint sample_rate);
alias InstrumentDestroy = fn void (InstrumentHandle);
alias InstrumentHandleEvent = fn void (InstrumentHandle, Event);
alias InstrumentRender = fn void (InstrumentHandle, Sample *, usz);

struct InstrumentVTable
{
	InstrumentInit init;
	InstrumentDestroy destroy;
	InstrumentHandleEvent handle_event;
	InstrumentRender render;
}

alias InstrumentGetVTable = fn InstrumentVTable* (); // exported by the plugin
