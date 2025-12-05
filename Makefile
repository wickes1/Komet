.PHONY: build run clean

build:
	swift build

run: build
	.build/debug/Komet

clean:
	swift package clean
