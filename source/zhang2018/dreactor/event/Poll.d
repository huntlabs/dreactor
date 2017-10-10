/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module zhang2018.dreactor.event.Poll;

import zhang2018.dreactor.event.Event;
import zhang2018.dreactor.time.Timer;

__gshared static this(){

	import core.sys.posix.signal;
	signal(SIGPIPE, SIG_IGN);
	signal(SIGHUP , SIG_IGN);
	signal(SIGTERM , SIG_IGN);
}

alias PollFunc = void delegate();

interface Poll
{
	bool addEvent(Event event , int fd , IOEventType type);
	bool delEvent(Event event , int fd , IOEventType type);
	bool modEvent(Event event , int fd , IOEventType type);

	bool poll(int milltimeout);

	TimerFd addTimer(TimerFunc func , ulong interval , WheelType type);
	void delTimer(TimerFd fd);

	void addFunc(PollFunc func);
	void delFunc(PollFunc func);

	// thread 
	void start();
	void stop();
	void wait();
}


interface Group
{
	Poll[] polls();
	void start();
	void stop();	
	void wait();	
}