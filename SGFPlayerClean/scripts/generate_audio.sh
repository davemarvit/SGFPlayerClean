#!/bin/bash

# Directory Setup
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTPUT_DIR="$SCRIPT_DIR/../Assets/Audio"
mkdir -p "$OUTPUT_DIR"

# Voice Selection
VOICE="Samantha" 
# Other options: "Daniel" (UK Male), "Tessa" (SA Female), "Alex" (Classic)

# Helper Function
generate_phrase() {
    local filename="$1"
    local phrase="$2"
    echo "Generating '$filename'..."
    say -v "$VOICE" "$phrase" -o "$OUTPUT_DIR/$filename"
}

echo "=== Generating Audio Assets in $OUTPUT_DIR ==="

# Game Lifecycle
generate_phrase "game_started.aiff" "Game Started"
generate_phrase "game_over.aiff" "Game Over"
generate_phrase "you_win.aiff" "You Win"
generate_phrase "you_lose.aiff" "You Lost"
generate_phrase "won_resignation.aiff" "You won by resignation"
generate_phrase "lost_resignation.aiff" "You lost by resignation"
generate_phrase "won_timeout.aiff" "You won by timeout"
generate_phrase "lost_timeout.aiff" "You lost by timeout"
generate_phrase "draw.aiff" "It is a draw"

# Clock / Timer
generate_phrase "ten_seconds.aiff" "Ten seconds left"
generate_phrase "countdown_10.aiff" "Ten"
generate_phrase "countdown_09.aiff" "Nine"
generate_phrase "countdown_08.aiff" "Eight"
generate_phrase "countdown_07.aiff" "Seven"
generate_phrase "countdown_06.aiff" "Six"
generate_phrase "countdown_05.aiff" "Five"
generate_phrase "countdown_04.aiff" "Four"
generate_phrase "countdown_03.aiff" "Three"
generate_phrase "countdown_02.aiff" "Two"
generate_phrase "countdown_01.aiff" "One"
generate_phrase "timeout.aiff" "You're out of time"
generate_phrase "byoyomi_start.aiff" "You have entered [[inpt PHON]]bYO-YOm1IY[[inpt TEXT]] time" 
# Note: "bYO-YOm1IY" is a rough approximation for "byoh-YOH-mee" using Apple's phoneme syntax if supported, 
# otherwise simple text "Byoh-Yoh-Me" might be safer. Let's try simple phonetic spelling first.
generate_phrase "byoyomi_simple.aiff" "You have entered Byoh-Yoh-Me time"

# Periods
generate_phrase "periods_1.aiff" "You have one period left"
generate_phrase "periods_2.aiff" "You have two periods left"
generate_phrase "periods_3.aiff" "You have three periods left"
generate_phrase "periods_4.aiff" "You have four periods left"
generate_phrase "periods_5.aiff" "You have five periods left"

# Game Events
generate_phrase "your_move.aiff" "Your move"
generate_phrase "pass.aiff" "Pass"
generate_phrase "game_restarted.aiff" "Game restarted"
generate_phrase "opponent_disconnected.aiff" "Opponent disconnected"
generate_phrase "opponent_connected.aiff" "Connected"

# Undo / Connection
generate_phrase "undo_requested.aiff" "Undo requested"
generate_phrase "undo_accepted.aiff" "Undo accepted"
generate_phrase "undo_refused.aiff" "Undo refused"
generate_phrase "connection_lost.aiff" "Connection lost"
generate_phrase "connection_restored.aiff" "Connection restored"

echo "=== Done! ==="
