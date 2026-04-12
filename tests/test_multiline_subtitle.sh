#!/bin/bash
# Test script for multi-line tab subtitles in vertical tab bar.
# Usage: bash tests/test_multiline_subtitle.sh

# Set tab title with multi-line subtitle using OSC 1 (icon/tab title).
# The first line becomes the title; everything after the first \n becomes the subtitle.

echo "=== Test 1: Single-line subtitle ==="
printf '\e]1;My Title\nOne subtitle line\a'
read -p "Press Enter for next test..."

echo "=== Test 2: Three-line subtitle ==="
printf '\e]1;My Title\nSubtitle line 1\nSubtitle line 2\nSubtitle line 3\a'
read -p "Press Enter for next test..."

echo "=== Test 3: Long wrapping subtitle ==="
printf '\e]1;My Title\nThis is a very long subtitle that should word-wrap across multiple lines in the vertical tab bar\a'
read -p "Press Enter for next test..."

echo "=== Test 4: Many lines ==="
printf '\e]1;Build Status\nLine 1: compiling\nLine 2: linking\nLine 3: testing\nLine 4: packaging\nLine 5: done\a'
read -p "Press Enter for next test..."

echo "=== Test 5: Reset to simple title ==="
printf '\e]1;Normal Title\a'
echo "Done."
