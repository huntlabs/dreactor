/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module zhang2018.dreactor.time.Timer;


alias TimerFd = Object;

enum WheelType{
	WHEEL_ONESHOT,
	WHEEL_PERIODIC,
};


alias TimerFunc = void delegate(TimerFd fd);
