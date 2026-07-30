module fras::queue @public;

import std::atomic;

faultdef QUEUE_EMPTY, QUEUE_FULL;

<* @require (CAPACITY & (CAPACITY - 1)) == 0 *>
struct Queue <Type, CAPACITY>
{
	Type[CAPACITY] data;
	Atomic{usz} head, tail;
}

fn void? Queue.enqueue (Queue *q, Type item)
{
	usz t = q.tail.load (RELAXED);
	usz h = q.head.load (ACQUIRE);

	if (t - h >= CAPACITY) return QUEUE_FULL~;

	q.data[t & (CAPACITY - 1)] = item;
	q.tail.store (t + 1, RELEASE);
}

fn Type*? Queue.front (Queue *q)
{
	usz h = q.head.load (RELAXED);
	usz t = q.tail.load (ACQUIRE);

	if (t == h) return QUEUE_EMPTY~;

	return &q.data[h & (CAPACITY - 1)];
}

fn Type? Queue.dequeue (Queue *q)
{
	usz h = q.head.load (RELAXED);
	usz t = q.tail.load (ACQUIRE);

	if (t == h) return QUEUE_EMPTY~;

	Type item = q.data[h & (CAPACITY - 1)];

	q.head.store (h + 1, RELEASE);

	return item;
}
