﻿/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module zhang2018.dreactor.event.GroupPoll;

import zhang2018.dreactor.event.Poll;
import zhang2018.dreactor.event.Epoll;
import zhang2018.dreactor.event.Select;

import std.random;
import std.parallelism;
import std.conv;

version (linux)
{
	alias DefaultPoll = Epoll;
}
else
{
	alias DefaultPoll = Select;
}

class GroupPoll(T = DefaultPoll) : Group
{
	this(int timeout = 10,  int work_numbers = totalCPUs )
	{
		while (work_numbers--)
			_works_polls ~= new T(timeout);

	}

	~this()
	{
		_works_polls.destroy();
	}

	Poll[] polls()
	{
		return _works_polls;
	}

	void start()
	{

		foreach (ref t; _works_polls)
			t.start();

	}

	void stop()
	{
		foreach (ref t; _works_polls)
			t.stop();
	}

	void wait()
	{
		foreach (ref t; _works_polls)
			t.wait();
	}


	private Poll[] _works_polls;

}
