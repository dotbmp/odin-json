when ODIN_OS == "windows" do import w32 "core:sys/windows.odin";

import "core:math.odin"

ticks :: inline proc() -> u64 {
    ticks: u64;
    w32.query_performance_counter(cast(^i64) &ticks);
    return ticks;
}

Day    :: enum int { Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday }
Month  :: enum int { January, February, March, April, May, June, July, August, September, October, November, December }
Season :: enum int { Winter, Spring, Summer, Autumn }

to_24_hour :: inline proc(hour: int, pm: bool) -> int do return pm ? (hour == 12 ? hour : hour + 12) : (hour == 12 ? 0 : hour);
to_12_hour :: inline proc(hour: int) -> (h: int, pm: bool) do return hour >= 12 ? (hour == 12 ? 12 : hour - 12) : (hour == 0 ? 12 : hour), hour >= 12;

forfeit :: inline proc() do w32.sleep(0); // forfeits remaining time in OS timeslot

Duration :: distinct f64;

sleep :: inline proc(d: Duration) do w32.sleep(cast(i32)math.round(ms(d)));

years            :: proc[from_years,   duration_years,   to_years];
months           :: proc[from_months,  duration_months,  to_months];
weeks            :: proc[from_weeks,   duration_weeks,   to_weeks];
days             :: proc[from_days,    duration_days,    to_days];
hours            :: proc[from_hours,   duration_hours,   to_hours];
minutes          :: proc[from_minutes, duration_minutes, to_minutes];
seconds          :: proc[from_seconds, duration_seconds, to_seconds];
ms               :: proc[from_ms,      duration_ms,      to_ms];
ns               :: proc[from_ns,      duration_ns,      to_ns];

from_years       :: inline proc(n: f64) -> Duration do return    days(n *  365);
from_months      :: inline proc(n: f64) -> Duration do return    days(n *   28);
from_weeks       :: inline proc(n: f64) -> Duration do return    days(n *    7);
from_days        :: inline proc(n: f64) -> Duration do return   hours(n *   24);
from_hours       :: inline proc(n: f64) -> Duration do return minutes(n *   60);
from_minutes     :: inline proc(n: f64) -> Duration do return seconds(n *   60);
from_seconds     :: inline proc(n: f64) -> Duration do return      ms(n * 1000);
from_ms          :: inline proc(n: f64) -> Duration do return      ns(n * 1000);
from_ns          :: inline proc(n: f64) -> Duration do return  cast(Duration) n;

duration_years   :: inline proc(n: int) -> Duration do return   years(cast(f64) n);
duration_months  :: inline proc(n: int) -> Duration do return  months(cast(f64) n);
duration_weeks   :: inline proc(n: int) -> Duration do return   weeks(cast(f64) n);
duration_days    :: inline proc(n: int) -> Duration do return    days(cast(f64) n);
duration_hours   :: inline proc(n: int) -> Duration do return   hours(cast(f64) n);
duration_minutes :: inline proc(n: int) -> Duration do return minutes(cast(f64) n);
duration_seconds :: inline proc(n: int) -> Duration do return seconds(cast(f64) n);
duration_ms      :: inline proc(n: int) -> Duration do return      ms(cast(f64) n);
duration_ns      :: inline proc(n: int) -> Duration do return      ns(cast(f64) n);

to_years         :: inline proc(d: Duration) -> f64 do return    days(d) /  365; // leap years make this an estimate (365.25???)
to_months        :: inline proc(d: Duration) -> f64 do return    days(d) /   28; // varying months make this an estimate
to_weeks         :: inline proc(d: Duration) -> f64 do return    days(d) /    7;
to_days          :: inline proc(d: Duration) -> f64 do return   hours(d) /   24;
to_hours         :: inline proc(d: Duration) -> f64 do return minutes(d) /   60;
to_minutes       :: inline proc(d: Duration) -> f64 do return seconds(d) /   60;
to_seconds       :: inline proc(d: Duration) -> f64 do return      ms(d) / 1000;
to_ms            :: inline proc(d: Duration) -> f64 do return      ns(d) / 1000;
to_ns            :: inline proc(d: Duration) -> f64 do return       cast(f64) d;

DurationData :: struct {
    years:   int,
    months:  int,
    weeks:   int,
    days:    int,
    hours:   int,
    minutes: int,
    seconds: int,
    ms:      int,
    ns:      int,
}

get_duration_data :: proc(d: Duration) -> DurationData {
    data: DurationData;

    data.years = cast(int) math.floor(years(d));
    d -= years(data.years);

    data.months = cast(int) math.floor(months(d));
    d -= months(data.months);

    data.weeks = cast(int) math.floor(weeks(d));
    d -= weeks(data.weeks);

    data.days = cast(int) math.floor(days(d));
    d -= days(data.days);

    data.hours = cast(int) math.floor(hours(d));
    d -= hours(data.hours);

    data.minutes = cast(int) math.floor(minutes(d));
    d -= minutes(data.minutes);

    data.seconds = cast(int) math.floor(seconds(d));
    d -= seconds(data.seconds);

    data.ms = cast(int) math.floor(ms(d));
    d -= ms(data.ms);

    data.ns = cast(int) d;

    return data;
}

get_duration :: proc(data: DurationData) -> Duration {
    d: Duration;

    d +=     years(data.years);
    d +=   months(data.months);
    d +=     weeks(data.weeks);
    d +=       days(data.days);
    d +=     hours(data.hours);
    d += minutes(data.minutes);
    d += seconds(data.seconds);
    d +=           ms(data.ms);
    d +=           ns(data.ns);

    return d;
}

Timer :: struct {
    ms_frequency: f64,
    start_ticks:  u64,
}

make_timer :: inline proc() -> Timer {
    timer: Timer;
    w32.query_performance_frequency(cast(^i64) &timer.start_ticks);
    timer.ms_frequency = cast(f64) timer.start_ticks;
    start(&timer);
    return timer;
}

start :: inline proc(timer: ^Timer) do timer.start_ticks = ticks();

query :: inline proc(timer: ^Timer, reset := false) -> Duration {
    t := ticks();

    res := cast(Duration) (
        (cast(f64) (t - timer.start_ticks)) /
        (timer.ms_frequency / 1000000)
    );

    if reset do start(timer);

    return res;
}
