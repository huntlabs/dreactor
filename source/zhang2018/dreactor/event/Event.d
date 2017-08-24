/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */

module zhang2018.dreactor.event.Event;

enum IOEventType
{
	IO_EVENT_NONE = 0,
	IO_EVENT_READ = 1 << 0,
	IO_EVENT_WRITE = 1 << 1,
	IO_EVENT_ERROR = 1 << 2
}


interface Event
{
	bool onWrite();
    bool onRead();
    bool onClose();

	bool isReadyClose();
}
