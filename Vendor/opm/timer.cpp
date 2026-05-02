/*
 * Copyright (c) 2026
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#include "timer.h"
#include <cstdio>

namespace opm {

Timer::Timer() 
    : clock_freq_(0), timer_a_value_(0), timer_a_count_(0),
      timer_a_load_(false), timer_a_enable_(false),
      timer_a_flag_(false), timer_a_active_(false),
      timer_b_value_(0), timer_b_count_(0),
      timer_b_load_(false), timer_b_enable_(false),
      timer_b_flag_(false), timer_b_active_(false) {
}

void Timer::Init(uint32_t clock_freq) {
    clock_freq_ = clock_freq;
}

void Timer::SetTimerA(uint16_t value) {
    timer_a_value_ = value & 0x3FF;
}

void Timer::SetTimerB(uint8_t value) {
    timer_b_value_ = value & 0xFF;
}

void Timer::LoadTimerA(bool load) {
    timer_a_load_ = load;
    if (load) {
        timer_a_count_ = GetTimerAPeriod();
        timer_a_active_ = true;
    }
}

void Timer::LoadTimerB(bool load) {
    timer_b_load_ = load;
    if (load && !timer_b_active_) {
        timer_b_count_ = GetTimerBPeriod();
        timer_b_active_ = true;
    }
}

void Timer::EnableTimerA(bool enable) {
    timer_a_enable_ = enable;
    if (!enable) {
        timer_a_flag_ = false;
    }
}

void Timer::EnableTimerB(bool enable) {
    timer_b_enable_ = enable;
    if (!enable) {
        timer_b_flag_ = false;
    }
}

void Timer::ResetTimerAFlag() {
    timer_a_flag_ = false;
}

void Timer::ResetTimerBFlag() {
    timer_b_flag_ = false;
}

uint32_t Timer::GetTimerAPeriod() const {
    if (timer_a_value_ >= 1024 || clock_freq_ == 0) return 0xFFFFFFFF;
    uint64_t ticks = 64ULL * (1024 - timer_a_value_);
    return static_cast<uint32_t>((ticks * 1000000ULL) / clock_freq_);
}

uint32_t Timer::GetTimerBPeriod() const {
    if (clock_freq_ == 0) return 0xFFFFFFFF;
    uint64_t ticks = 1024ULL * (256 - timer_b_value_);
    return static_cast<uint32_t>((ticks * 1000000ULL) / clock_freq_);
}

bool Timer::Advance(uint32_t microseconds) {
    bool interrupted = false;
    
    if (timer_a_active_ && timer_a_enable_) {
        if (timer_a_count_ <= microseconds) {
            timer_a_flag_ = true;
            interrupted = true;
            timer_a_count_ = GetTimerAPeriod();
        } else {
            timer_a_count_ -= microseconds;
        }
    }
    
    if (timer_b_active_ && timer_b_enable_) {
        if (timer_b_count_ <= microseconds) {
            timer_b_flag_ = true;
            interrupted = true;
            timer_b_count_ = GetTimerBPeriod();
        } else {
            timer_b_count_ -= microseconds;
        }
    }
    
    return interrupted;
}

uint32_t Timer::GetNextEventTime() const {
    uint32_t min_time = 0xFFFFFFFF;
    
    if (timer_a_active_ && timer_a_enable_) {
        if (timer_a_count_ > 0 && timer_a_count_ < min_time) {
            min_time = timer_a_count_;
        }
    }
    
    if (timer_b_active_ && timer_b_enable_) {
        if (timer_b_count_ > 0 && timer_b_count_ < min_time) {
            min_time = timer_b_count_;
        }
    }
    
    return (min_time == 0xFFFFFFFF) ? 0 : min_time;
}

void Timer::Reset() {
    timer_a_count_ = 0;
    timer_a_active_ = false;
    timer_a_flag_ = false;
    timer_b_count_ = 0;
    timer_b_active_ = false;
    timer_b_flag_ = false;
}

} // namespace opm
