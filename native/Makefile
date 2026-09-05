CXX ?= g++
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wall -Wextra -Wpedantic -Wno-c++11-narrowing
ifeq ($(CXX),g++)
CXXFLAGS += --no-gnu-unique
endif

INCLUDES := $(shell pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon)
TARGET := orbit-drag.so
SOURCE := orbit_drag.cpp

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCE) DragTracker.hpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(INCLUDES) $< -o $@

clean:
	$(RM) $(TARGET)
